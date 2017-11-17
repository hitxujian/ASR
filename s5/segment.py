# -*- coding: utf-8 -*-
import sys
import os
from sys import argv
import jieba

reload(sys)
sys.setdefaultencoding('utf-8')

jieba.load_userdict('/data02/data/corpus/newdict/new_thchs.txt')


fp = open('/data02/data/corpus/newdict/new_thchs.txt','r')
phonedict = {}
for line in fp:
  list11 = line.strip()
  if list11 not in phonedict:
    phonedict[list11]  = 1

  else:
    phonedict[list11] =  1

def phonetic(str,fp):
  l = len(str)
  L = len(str)
  while l > 0:
    if str[0:l] not in phonedict:
      if str[l-1] == '#':
        l = l-1
      else:
        l = l-3
      if l <= 0:
        #print str
        flag =  1
        return flag
    else:
      if l == L:
        fp.write(' '+str[0:l])
        break 
      else:
        fp.write(' '+str[0:l])
        flag1 = phonetic(str[l:L],fp)
        return flag1
        break
'''
test_text="开启摆风" 


seg_list = jieba.cut(test_text,cut_all=False)
seg_list = " ".join(seg_list)
print seg_list
'''

fp1 = open(argv[1],'r')
fp2 = open('comword.txt','w')
#fp3 = open('log','w')
for line in fp1:
  seg_list = line.strip().split(' ')
  id = seg_list[0]
  word_list = jieba.cut(''.join(seg_list[1:]),cut_all=False)
  #print len(word_list)  
  word_list = " ".join(word_list)
  #list1 = word_list.split(' ')
  fp2.write(id+' '+word_list+'\n')
  

fp1.close()
fp2.close()
#fp3.close()

fp3 = open('comword.txt','r')
fp4 = open(argv[2],'w')

for lines in fp3:
  words = lines.strip().split(' ')
  fp4.write(words[0])
  for word in words[1:]:
    if word in phonedict:
      fp4.write(' ' + word)
    else:
      flag = phonetic(word,fp4)
      if flag: 
        print lines
        break
  fp4.write('\n')

fp3.close()
fp4.close()
os.remove('comword.txt')

  
