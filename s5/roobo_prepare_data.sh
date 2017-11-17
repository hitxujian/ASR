#!/bin/bash

. ./env.sh

data_src_wav_dir=$data_src_root/data_aishell/wav
data_src_transcript_dir=$data_src_root/data_aishell/transcript
# 分词标注文件
data_src_transcript=$data_src_transcript_dir/aishell_transcript_v0.8.txt

# 训练集数据相关文件(源数据除外)所在目录, 注意源数据音频已经预先按文件夹分类了
data_train_dir=$data_root/local/train
data_test_dir=$data_root/local/test
data_dev_dir=$data_root/local/dev
tmp_dir=$data_root/local/tmp
# 确认文件夹存在
mkdir -p $data_train_dir
mkdir -p $data_test_dir
mkdir -p $data_dev_dir
mkdir -p $tmp_dir

# 判断数据源音频文件与分词文件是否存在
# 源音频文件 /data01/os/chaopei/kaldi-data/data_aishell/wav
# 分词文件 /data01/os/chaopei/kaldi-data/data_aishell/transcript
if [ ! -d $data_src_wav_dir ] || [ ! -f $data_src_transcript ]; then
    echo "[prepare_data.sh]: Error, '$data_src_wav_dir' or '$data_src_transcript' not exist."
    exit 1;
fi

# 在数据源音频文件夹中查找所有 .wav 文件，将文件名输入到临时文件中
find $data_src_wav_dir -iname "*.wav" > $tmp_dir/wav.flist

# 检查数据个数，在这里我们不再检查了
# n=`cat $tmp_dir/wav.flist | wc -l`
# [ $n -ne 141925 ] && echo Warning: expected 141925 data data files, found $n

# 分别把文件名列表放入对应的文件夹的flist中
grep -i "wav/train" $tmp_dir/wav.flist > $data_train_dir/wav.flist || exit 1;
grep -i "wav/dev" $tmp_dir/wav.flist > $data_dev_dir/wav.flist || exit 1;
grep -i "wav/test" $tmp_dir/wav.flist > $data_test_dir/wav.flist || exit 1;

# $data_root/local/tmp 就是为了倒腾数据，用完删除
rm -r $tmp_dir

# 处理标注数据
for dir in $data_train_dir $data_test_dir $data_dev_dir; do
    echo "Preparing $dir transcription"
    # 将文件名去除后缀名后提取出来作为 utterance id
    # utt.list: <wav_filename>
    sed -e 's/\.wav//' $dir/wav.flist | awk -F '/' '{print $NF}' > $dir/utt.list
    # 数据源所在文件夹是按照 .../<speaker_id>/<utterance_id>.wav 放置与取名的, 最后两列即speaker_id和utterance_id
    # utt2spk_all: <utterance_id> <speaker_id>
    sed -e 's/\.wav//' $dir/wav.flist | awk -F '/' '{i=NF-1;printf("%s %s\n",$NF,$i)}' > $dir/utt2spk_all
    # wav.scp_all: <utterance_id> <file>
    paste -d' ' $dir/utt.list $dir/wav.flist > $dir/wav.scp_all
    # 从总标注信息里整理指定集的数据到 transcripts.txt
    # transcripts.txt: <utterance_id> <transcript>
    utils/filter_scp.pl -f 1 $dir/utt.list $data_src_transcript > $dir/transcripts.txt
    # utt2spk与wav.scp排序存储
    utils/filter_scp.pl -f 1 $dir/utt.list $dir/utt2spk_all | sort -u > $dir/utt2spk
    utils/filter_scp.pl -f 1 $dir/utt.list $dir/wav.scp_all | sort -u > $dir/wav.scp
    # transcripts.txt也排序存为text
    sort -u $dir/transcripts.txt > $dir/text
    utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt
done

# 整体在local中准备好后拷贝到正式数据文件夹 /data/
mkdir -p data/train data/dev data/test

for f in spk2utt utt2spk wav.scp text; do
    cp $data_train_dir/$f data/train/$f || exit 1;
    cp $data_dev_dir/$f data/dev/$f || exit 1;
    cp $data_test_dir/$f data/test/$f || exit 1;
done

echo "$0: AISHELL data preparation succeeded"
exit 0;
