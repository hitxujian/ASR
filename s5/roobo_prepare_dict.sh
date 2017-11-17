#!/bin/bash

:<<README
数据源中我们有词典 lexicon.txt：如
    SIL sil
    <SPOKEN_NOISE> sil
    啊 aa a1
    啊 aa a2
    ...
    作权 z uo4 q van2
    作如 z uo4 r u2
该脚本可以从词典中提取所有音素，初始化音素文件：silence_phones.txt、nonsilence_phones.txt、optional_silence.txt
根据上述音素文件，初始化决策树所需问题文件 extra_questions.txt
README

. ./env.sh
# prepare_dict.sh /data01/os/chaopei/kaldi-data
# data src dir, downloaded by prepare_data.sh

# In this case, data_src_dir=/data01/os/chaopei/kaldi-data
data_src_dict_dir=$data_src_root/data_src_root

# dictionary copy to data/local/dict/
dict_dir=$data_root/local/dict
cp $data_src_dict_dir/lexicon.txt $dict_dir/

# 探索词典中所用到的所有音素
cat $dict_dir/lexicon.txt |\
    awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}' |\
    # 排序
    sort -u |\
    # 这里总觉得不太对
    perl -e '
    my %ph_cl;
    while (<STDIN>) {
        chomp($_);
        $phone = $_;
        next if ($phone eq "sil");
        if (exists $ph_cl{$phone}) { push(@{$ph_cl{$phone}}, $_)  }
        else { $ph_cl{$phone} = [$_]; }
    }
    foreach $key ( keys %ph_cl ) {
        print "@{ $ph_cl{$key} }\n"
    }
    ' |\
    # 排序后保存至 nonsilence_phones.txt
    sort -k1 > $dict_dir/nonsilence_phones.txt  || exit 1;
# 静音音素
echo sil > $dict_dir/silence_phones.txt
# ???
echo sil > $dict_dir/optional_silence.txt

# No "extra questions" in the input to this setup, as we don't
# have stress or tone 

# extra_questions, 静音
cat $dict_dir/silence_phones.txt |\
    awk '{printf("%s ", $1);} END{printf "\n";}' > $dict_dir/extra_questions.txt || exit 1;
# extra_questions, 普通音素
cat $dict_dir/nonsilence_phones.txt |\
    perl -e '
    while(<>) {
        foreach $p (split(" ", $_)) {
            $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; 
        }
    }
    foreach $l (values %q) {
        print "$l\n";
    }
    ' \ >> $dict_dir/extra_questions.txt || exit 1;

echo "$0: roobo dict preparation succeeded"
exit 0;
