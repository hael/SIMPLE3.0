!#/usr/bin/bash

SIMPLE_PATH=~/el85_scratch/eagerm/SIMPLE3.0/build
module load git cmake fftw relion gctf/1.06_cuda8 chimera eman/2.2
export PATH=$SIMPLE_PATH/bin:$PATH
cd ~/el85_scratch/stars_from_matt

mkdir simple_convert_star
cd simple_convert_star
## make new project

simple_exec prg=new_project projname=micrographs_all_gctf
cd micrographs_all_gctf
simple_exec prg=importstar_project starfile=../../micrographs_all_gctf.star

       
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=CtfFind
cd CtfFind
simple_exec prg=importstar_project starfile=../../CtfFind/GCTF_Initial/micrographs_ctf.star


cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Class2D
cd Class2D
simple_exec prg=importstar_project starfile=../../Class2D/Class2D_1st
#run_it*_(data|model|optimiser|sampling).star run_it*_classes.mrcs

 
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=InitialModel
cd InitialModel
simple_exec prg=importstar_project starfile=../../InitialModel/ 


cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=PostProcess
cd PostProcess
simple_exec prg=importstar_project starfile=../../PostProcess/Post/postprocess.star


cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=ManualPick
cd ManualPick
# simple_exec prg=importstar_project starfile=../../ManualPick/ManualPick/coords_suffix_manualpick.star --> this contains one line: ./CtfFind/job002/micrographs_ctf.star
simple_exec prg=importstar_project starfile=../../ManualPick/ManualPick/micrographs_selected.star


    
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Refine3D
cd Refine3D
simple_exec prg=importstar_project starfile=../../Refine3D/Refine3D_1st/run_ct19_data.star
# run_ct19_it019_data.star
# run_it000_data.star
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Refine3D_Mask_2nd
cd Refine3D_Mask_2nd
simple_exec prg=importstar_project starfile=../../Refine3D/Refine3D_Mask_2nd/run_it018_data.star


            
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Extract
cd Extract
simple_exec prg=importstar_project starfile=../../Extract/364Box_Extract_LocalCTF/particles.star 

# cd ~/el85_scratch/stars_from_matt/simple_convert_star
# simple_exec prg=new_project projname=MaskCreate
# cd MaskCreate
# simple_exec prg=importstar_project starfile=../../MaskCreate/  

  
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Select
cd Select
simple_exec prg=importstar_project starfile=../../Select/1stCut/particles.star
simple_exec prg=importstar_project starfile=../../Select/1stCut/class_averages.star
            
cd ~/el85_scratch/stars_from_matt/simple_convert_star
simple_exec prg=new_project projname=Import
cd Import
simple_exec prg=importstar_project starfile=../../Import/Import/micrographs.star
simple_exec prg=importstar_project starfile=../../Import/GautoMatch_1st/coords_suffix_automatch.star
simple_exec prg=importstar_project starfile=../../Import/LocalCTF_ParticlePositionImport/coords_suffix_local.star



## cryosparc
simple_exec prg=new_project projname=cryosparc_movies
cd cryosparc_movies
echo "../../cryosparc_exp000325_002.mrc" > filetab.txt
simple_exec prg=import_movies filetab=filetab.txt cs=2.7 kv=300 fraca=0.1 smpd=1

