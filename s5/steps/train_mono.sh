#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0


# To be run from ..
# Flat start and monophone training, with delta-delta features.
# This script applies cepstral mean normalization (per speaker).

# Begin configuration section.
nj=4 # 并行数 4
cmd=cmd.sh # 一般来说，我们不采用分布式
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
num_iters=40    # Number of iterations of training
max_iter_inc=30 # Last iter to increase #Gauss on.
totgauss=1000 # Target #Gaussians.
careful=false
boost_silence=1.0 # Factor by which to boost silence likelihoods in alignment
realign_iters="1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 23 26 29 32 35 38";
config= # name of config file.
stage=-4
power=0.25 # exponent to determine number of gaussians from occurrence counts
norm_vars=false # deprecated, prefer --cmvn-opts "--norm-vars=false"
cmvn_opts=  # can be used to add extra options to cmvn.
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
  echo "Usage: steps/train_mono.sh [options] <data-dir> <lang-dir> <exp-dir>"
  echo " e.g.: steps/train_mono.sh data/train.1k data/lang exp/mono"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --nj <nj>                                        # number of parallel jobs"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  exit 1;
fi

data=$1 # 训练数据目录 /data/train
lang=$2 # 音素、词典、语言模型目录 /data/lang
dir=$3 # 输出exp目录 /exp/mono

oov_sym=`cat $lang/oov.int` || exit 1;

mkdir -p $dir/log
echo $nj > $dir/num_jobs
sdata=$data/split$nj;
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $data $nj || exit 1; # 如果数据不是最新的，按Job数分割数据

cp $lang/phones.txt $dir || exit 1;

$norm_vars && cmvn_opts="--norm-vars=true $cmvn_opts"
echo $cmvn_opts  > $dir/cmvn_opts # keep track of options to CMVN.

feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |"
example_feats="`echo $feats | sed s/JOB/1/g`";
echo "example_feats=$example_feats" # 打印出来瞧瞧
echo "$0: Initializing monophone system."

[ ! -f $lang/phones/sets.int ] && exit 1;
shared_phones_opt="--shared-phones=$lang/phones/sets.int"

if [ $stage -le -3 ]; then
  # Note: JOB=1 just uses the 1st part of the features-- we only need a subset anyway.
  if ! feat_dim=`feat-to-dim "$example_feats" - 2>/dev/null` || [ -z $feat_dim ]; then
    feat-to-dim "$example_feats" -
    echo "error getting feature dimension"
    exit 1;
  fi
  $cmd JOB=1 $dir/log/init.log \
    gmm-init-mono $shared_phones_opt "--train-feats=$feats subset-feats --n=10 ark:- ark:-|" $lang/topo $feat_dim \
    $dir/0.mdl $dir/tree || exit 1;
fi

numgauss=`gmm-info --print-args=false $dir/0.mdl | grep gaussians | awk '{print $NF}'`
incgauss=$[($totgauss-$numgauss)/$max_iter_inc] # per-iter increment for #Gauss
echo "numgauss=$numgauss, totgauss=$totgauss, max_iter_inc=$max_iter_inc, incgauss=$incgauss"

# 构造训练的网络，从源码级别分析，是每个句子构造一个phone level 的fst网络。

# $sdaba/JOB/text 中包含对每个句子的单词(words level)级别标注， L.fst是字典对于的fst表示，
# 作用是将一串的音素（phones）转换成单词（words）

# 构造monophone解码图就是先将text中的每个句子，生成一个fst（类似于语言模型中的G.fst，只是相对比较简单，
# 只有一个句子），然后和L.fst 进行composition 形成训练用的音素级别（phone level）fst网络（类似于LG.fst）。

# fsts.JOB.gz 中使用 key-value 的方式保存每个句子和其对应的fst网络，通过 key(句子) 就能找到这个句子的fst网络，
# value中保存的是句子中每两个音素之间互联的边（Arc）,例如句子转换成音素后，标注为："a b c d e f",
# 那么value中保存的其实是 a->b b->c c->d d->e e->f 这些连接（kaldi会为每种连接赋予一个唯一的id），
# 后面进行 HMM 训练的时候是根据这些连接的id进行计数，就可以得到转移概率。
if [ $stage -le -2 ]; then
  echo "$0: Compiling training graphs"
  $cmd JOB=1:$nj $dir/log/compile_graphs.JOB.log \
    compile-train-graphs --read-disambig-syms=$lang/phones/disambig.int $dir/tree $dir/0.mdl  $lang/L.fst \
    "ark:sym2int.pl --map-oov $oov_sym -f 2- $lang/words.txt < $sdata/JOB/text|" \
    "ark:|gzip -c >$dir/fsts.JOB.gz" || exit 1;
    # compile-train-graphs：
    #read-disambig-syms  $lang/phones/disambig.int
    #1  $dir/tree
    #2  $dir/0.mdl
    #3  $lang/L.fst
    #4  "ark:sym2int.pl --map-oov $oov_sym -f 2- $lang/words.txt < $sdata/JOB/text|"
    #5  "ark:|gzip -c >$dir/fsts.JOB.gz"
fi

if [ $stage -le -1 ]; then
  echo "$0: Aligning data equally (pass 0)"
  # 训练时需要将标注跟每一帧特征进行对齐，由于现在还没有可以用于对齐的模型，所以采用最简单的方法 -- 均匀对齐
  # 根据标注数目对特征序列进行等间隔切分，例如一个具有5个标注的长度为100帧的特征序列，则认为1-20帧属于第1个标注，21-40属于第2个...
  # 这种划分方法虽然会有误差，但待会在训练模型的过程中会不断地重新对齐。
  $cmd JOB=1:$nj $dir/log/align.0.JOB.log \
    align-equal-compiled "ark:gunzip -c $dir/fsts.JOB.gz|" "$feats" ark,t:-  \| \
    # 对对齐后的数据进行训练，获得中间统计量，每个任务输出到一个acc文件。
    # acc中记录跟HMM 和GMM 训练相关的统计量：
    # HMM 相关的统计量：两个音素之间互联的边（Arc） 出现的次数。
    #                 如上面所述，fst.JOB.gz 中每个key对于的value保存一个句子中音素两两之间互联的边。
    #                 gmm-acc-stats-ali 会统计每条边（例如a->b）出现的次数，然后记录到acc文件中。
    # GMM 相关的统计量：每个pdf-id 对应的特征累计值和特征平方累计值。
    #                 对于每一帧，都会有个对齐后的标注，gmm-acc-stats-ali 可以根据标注检索得到pdf-id,
    #                 每个pdf-id 对应的GMM可能由多个单高斯Component组成，会先计算在每个单高斯Component对应的分布下这一帧特征的似然概率（log-likes），称为posterior。
    #                 然后：
    #                    （1）把每个单高斯Component的posterior加到每个高斯Component的occupancy（占有率）计数器上，用于表征特征对于高斯的贡献度，
    #                        如果特征一直落在某个高斯的分布区间内，那对应的这个值就比较大；相反，如果一直落在区间外，则表示该高斯作用不大。
    #                        gmm-est中可以设置一个阈值，如果某个高斯的这个值低于阈值，则不更新其对应的高斯。
    #                        另外这个值（向量)其实跟后面GMM更新时候的高斯权重weight的计算相关。
    #                    （2）把这一帧数据加上每个单高斯Component的posterior再加到每个高斯的均值累计值上；
    #                        这个值（向量）跟后面GMM的均值更新相关。
    #                    （3）把这一帧数据的平方值加上posterior再加到每个单高斯Component的平方累计值上；
    #                        这个值（向量）跟后面GMM的方差更新相关。
    #                 最后将均值累计值和平方累计值写入到文件中。
    gmm-acc-stats-ali --binary=true $dir/0.mdl "$feats" ark:- \
    $dir/0.JOB.acc || exit 1;
    # align-equal-compiled
    #1  "ark:gunzip -c $dir/fsts.JOB.gz|"
    #2  "$feats"
    #3  ark,t:-
    # gmm-acc-stats-ali
    #binary  true
    #1  $dir/0.mdl
    #2  "$feats"
    #3  ark:-
    #4  $dir/0.JOB.acc
fi

# In the following steps, the --min-gaussian-occupancy=3 option is important, otherwise
# we fail to est "rare" phones and later on, they never align properly.
# 根据上面得到的统计量，更新每个GMM模型，AccumDiagGmm中occupancy_的值决定混合高斯模型中每个单高斯Component的weight；
# --min-gaussian-occupancy 的作用是设置occupancy_的阈值，如果某个单高斯Component的occupancy_低于这个阈值，那么就不会更新这个高斯，
# 而且如果 --remove-low-count-gaussians=true,则对应得单高斯Component会被移除。
if [ $stage -le 0 ]; then
  gmm-est --min-gaussian-occupancy=3  --mix-up=$numgauss --power=$power \
    $dir/0.mdl "gmm-sum-accs - $dir/0.*.acc|" $dir/1.mdl 2> $dir/log/update.0.log || exit 1;
    # gmm-est
    #min-gaussian-occupancy  3
    #mix-up  $numgauss
    #power  $power
    #1  $dir/0.mdl
    #2  "gmm-sum-accs - $dir/0.*.acc|"
    #3  $dir/1.mdl
    #4  2
  rm $dir/0.*.acc
fi


beam=6 # will change to 10 below after 1st pass
# note: using slightly wider beams for WSJ vs. RM.
x=1
while [ $x -lt $num_iters ]; do
  echo "$0: Pass $x"
  if [ $stage -le $x ]; then
    if echo $realign_iters | grep -w $x >/dev/null; then
      echo "$0: Aligning data"
      mdl="gmm-boost-silence --boost=$boost_silence `cat $lang/phones/optional_silence.csl` $dir/$x.mdl - |"
      $cmd JOB=1:$nj $dir/log/align.$x.JOB.log \
        gmm-align-compiled $scale_opts --beam=$beam --retry-beam=$[$beam*4] --careful=$careful "$mdl" \
        "ark:gunzip -c $dir/fsts.JOB.gz|" "$feats" "ark,t:|gzip -c >$dir/ali.JOB.gz" \
        || exit 1;
    fi
    $cmd JOB=1:$nj $dir/log/acc.$x.JOB.log \
      gmm-acc-stats-ali  $dir/$x.mdl "$feats" "ark:gunzip -c $dir/ali.JOB.gz|" \
      $dir/$x.JOB.acc || exit 1;

    $cmd $dir/log/update.$x.log \
      gmm-est --write-occs=$dir/$[$x+1].occs --mix-up=$numgauss --power=$power $dir/$x.mdl \
      "gmm-sum-accs - $dir/$x.*.acc|" $dir/$[$x+1].mdl || exit 1;
    rm $dir/$x.mdl $dir/$x.*.acc $dir/$x.occs 2>/dev/null
  fi
  if [ $x -le $max_iter_inc ]; then
     numgauss=$[$numgauss+$incgauss];
  fi
  beam=10
  x=$[$x+1]
done

( cd $dir; rm final.{mdl,occs} 2>/dev/null; ln -s $x.mdl final.mdl; ln -s $x.occs final.occs )


steps/diagnostic/analyze_alignments.sh --cmd "$cmd" $lang $dir
utils/summarize_warnings.pl $dir/log

steps/info/gmm_dir_info.pl $dir

echo "$0: Done training monophone system in $dir"

exit 0

# example of showing the alignments:
# show-alignments data/lang/phones.txt $dir/30.mdl "ark:gunzip -c $dir/ali.0.gz|" | head -4

