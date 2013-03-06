build_average_model
===================

Collection of scripts to create population-specific average anatomical models,
Method is described in 
VS Fonov, AC Evans, K Botteron, CR Almli, RC McKinstry, DL Collins and BDCG, Unbiased average age-appropriate atlases for pediatric studies, NeuroImage,Volume 54, Issue 1, January 2011, ISSN 1053–8119,
DOI: http://dx.doi.org/10.1016/j.neuroimage.2010.07.033

Relies on tools from minc_toolkit from https://github.com/BIC-MNI/minc-toolkit



HOW-TO
==================


1. prepare your data, all scans have to be linearly registered to stereotaxic space and brain should be extracted. Also intensities should be normalized so that white matter is around 100.

One use the standard pipeline ( https://github.com/vfonov/bic-pipelines )

After the files are prepared, create a text file with following format:

    <full path to subject 1 anatomical>,<full path to subject 1 mask>
    <full path to subject 2 anatomical>,<full path to subject 2 mask>
    ...
    <full path to subject N anatomical>,<full path to subject N mask>

assuming that you stored it into the file subjects.lst

2. to run the script :

    build_average_model.rb \
      -f 32,4,16,4,8,4,4,4,2,4 \
      -q <SGE queue> \
      --model <initial anatomical model> \
      --model-mask <initial anatomical model mask> \
      --list subjects.lst \
      --spline \
      -o <model directory>

      
this script will submit a lot of jobs on the SGE, using ```<SGE queue>``` and the output will be in the directory ```<model directory>```, final result will be
```<model directory>/avg_20.mnc``` for the anatomical average and ```<model directory>/avg_20_mask.mnc``` for the brain mask.

