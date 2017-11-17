:<<README
此脚本用来根据准备的训练数据训练语言模型, 运行此脚本前需确认词典和数据都已经准备好了
README

. ./env.sh

# 训练用标注数据
text=$data_root/local/train/text
# 词典
lexicon=$data_root/local/dict/lexicon.txt
# 检查标注和词典是否存在
for f in $text $lexicon; do
    [! -d $f] && echo "[$0]: no such file $f" && exit 1;
done

# 创建语言模型文件夹
dir=$data_root/local/lm
mkdir -p dir

# 计算训练数据中每个单词的数目（这两种写法效果差距不大，有些空格对齐不同，前者稍快）
cat $text | awk '{for(n=2;n<=NF;n++){ if(seen[$n]){ seen[$n]+=1; }else{ seen[$n]=1; } } } 
    END{ for(k in seen) print seen[k],k; }' |\
    sort -nr > $dir/word.counts || exit 1;
# cat $text | awk '{for(n=2;n<=NF;n++) print $n; }' | sort | uniq -c | sort -nr > $dir/word.counts || exit 1;

# 合并词典和分词标注，统计所有单词数目，不统计 “SIL”
cat $text | awk '{for(n=2;n<=NF;n++) print $n; }' | \
    cat - <(grep -w -v 'SIL' $lexicon | awk '{print $1}') | \
    sort | uniq -c | sort -nr > $dir/unigram.counts || exit 1;

# 对合并后的所有单词，创建单词对一个短字符的映射，对于BOS、EOS、UNKNOWN的音素，则简单的用A、B、C表示
cat $dir/unigram.counts  | awk '{print $2}' | get_word_map.pl "<s>" "</s>" "<SPOKEN_NOISE>" > $dir/word_map \
   || exit 1;
# 对于 get_word_map.pl
# This program reads in a file with one word
# on each line, and outputs a "translation file" of the form:
# word short-form-of-word
# on each line,
# where short-form-of-word is a kind of abbreviation of the word.
#
# It uses the letters a-z and A-Z, plus the characters from
# 128 to 255.  The first words in the file have the shortest representation.
#
# For convenience, it makes sure to give <s>, </s> and <UNK>
# a consistent labeling, as A, B and C respectively.
# set up character table and some variables.

# 把分词标注的所有单词都换为上一步的短字符
cat $text | awk -v wmap=$dir/word_map '{BEGIN{while((getline<wmap)>0)map[$1]=$2;} 
    {for(n=2;n<=NF;n++){ print map[$n]; if(n<NF){ print " "; }else{ print ""; }}}' |\
    gzip -c >$dir/train.gz || exit 1;

# 训练3-gram语言模型, 保存在
train_lm.sh --arpa --lmtype 3gram-mincount $dir || exit 1;

# LM is small enough that we don't need to prune it (only about 0.7M N-grams).
# Perplexity over 128254.000000 words is 90.446690

# note: output is
# data/local/lm/3gram-mincount/lm_unpruned.gz

exit 0
