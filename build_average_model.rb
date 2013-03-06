#! /usr/bin/env ruby
require 'BIC_BATCH'
require 'optparse'
require 'ostruct'
require 'pathname'
require 'fileutils'

def write_list(arr,file)
  File.open(file,'w') do |fh|
    fh.puts arr.join("\n")
  end
end

begin
  me=File::basename($0)
  bin_dir=File::dirname($0)+'/internal/'
  verbose=false
  spline=false
  disable_linear=true
  queue='wb221.q'
  iterations=1
  model=''          # original model
  model_mask=''
  non_linear_on=false
  output='model'     # output directory
  workdir='' 
  symmetric=false    # perform symmetric averaging
  build_mask=true    # 
  serial=false       #
  bet=false          # use bet for masking 
  avg_mask=true     # average individual masks to create model mask
  keep_xfms=true     # keep xfm files from each iteration
  import_masks=nil   # directrory to look for premade masks
  step=0
  fit_steps=Array.new
  fit_iter=Array.new
  log_dir=''
  file_list=''
  bandwidth=0.0
  log_euclidian=false
  patches=0
  stagger=false #make delays at the beginning of each massive parallel job
   # List of arguments.
	ops=OptionParser.new do |opts|
    opts.banner = "Usage: #{me} [Options] <file1> <file2> ..."
    opts.separator ""
    opts.separator "Options:"
		
		opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          	verbose = v
    end
          
		opts.on('-l', '--[no-]log', 'Use Log-Euclidian operations') do |v|
          	log_euclidian = v
    end
    
		opts.on('-f <fit_level 1>,<number of iterations>,<fit level 2>,<n>,<fit level 3>...',
                 '--fit <fit_level 1>,<number of iterations>,<fit level 2>,<n>,<fit level 3>', Array,
                 'non linear fitting level, use "0" for linear step') do |v|
            if v.size() & 1 == 1
              STDERR.print "exit in formating of fit levels"
              exit 1 
            end
            (0 .. v.size()/2-1).each do |i|
              fit_steps<< v[i*2].to_f
              fit_iter << v[i*2+1].to_i
            end
            non_linear_on=true
            puts fit_steps.join('|')
    end
#		opts.on('--keep_all_xmf', 'Keep All XFMs') do |k|
#          keep_xfms=k
#   end
    
    opts.on('--patches <n>',"Do patch based average instead of classic mean, with patch size n",Numeric) do |v|
      patches = v.to_i
    end
    
    
		opts.on('--serial', 'Execute jobs locally') do |v|
          	serial = v
    end
    
		opts.on('--symmetric', 'Build Symmetric model') do |v|
      symmetric = v
    end
    
    opts.on('--spline', 'Use spline resampling (itk_resample)') do |v|
      spline = v
    end
    
    opts.on('--bandwidth <f>', 'Use mean-shift algo with this bandwidth',Float) do |v|
      bandwidth=v
    end
    
    opts.on('-q <qname>','--queue <qname>','Queue to use for batch processing') do |q|
      queue=q
    end
    
    opts.on('--model <model>', '-m <model>', 'Initial model') do |m|
          	model=m
    end
          
    opts.on('--model-mask <model-mask>', 'Initial Model mask') do |m|
          	model_mask=m
    end
    
    opts.on('--list <file_list>','-l <file_list>','Input file list, format: file1[,mask1]\nfile2[,mask2]\n...') do |m|
      file_list=Pathname.new(m).realpath.to_s
    end
          
    opts.on('--import_masks <dir>', 'Import handmade masks from that dir (should have the same filenames)') do |m|
      import_masks=m
    end
    
		opts.on('--output <out>','-o <out>', "Output dir") do |o|
			    output=o.to_s
          puts "Output:"+output
    end
        
		opts.on('--workdir <out>','-w <out>', "Work dir (a large number of intermediate files goes there)") do |o|
			    workdir=o.to_s
          puts "Output:"+output
    end
        
	  opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
    end
	end
	ops.parse!(ARGV)
	if ARGV.length<1 && file_list.empty?
	 #puts "Usage: #{$0} <file1> <file2> ..."
   puts ops
	 exit 1
  end
 
  in_files=Array.new
  in_masks=Array.new
  
  if file_list.empty?
    ARGV.each do |f|
      p=Pathname.new(f)  
      in_files<< p.realpath.to_s
    end
  else
    File::open(file_list) do |fd|
      fd.each do |ln|
        ln.chomp!
        (file,mask)=ln.split(',')
        in_files<<file
        unless mask.nil?
          in_masks<<mask
        end
      end
    end
  end
  
  if in_files.size<2
    STDERR.puts "Number of input samples is below 2"
    exit 1
  end
  
  if in_masks.size>0 && in_masks.size!=in_files.size
    STDERR.puts "Number of masks and files mismatch!"
    exit 1
  end
  
  if ARGV.length>10
    puts "number of samples is more than 10, running staggered mode!"
    stagger=true
  end
  
  stagger_delay=2 # delay 2 sec /file
  FileUtils.mkdir_p output
  batch=Batch.new(queue, serial)
  prefix='bm_'+$$.to_s
  prev_step=nil
  pwd=Dir.pwd
  tmpdir=output+'/'
  if workdir.empty?
    workdir=output
  end
  
  tmpdir_w=workdir+'/'
  FileUtils.mkdir_p tmpdir_w
  if log_dir.empty?
    log_dir=tmpdir
  end
  puts "TmpDir: #{tmpdir}"
  if model.empty? 
    cur_model=in_files[0]
    cur_model_mask=in_masks[0] if model_mask.empty? && !in_masks[0].nil? && !in_masks[0].empty?
  else
    cur_model=model
    cur_model_mask=model_mask 
  end
  
  flip_step=''
  # if symmetric, flip the volumes 
  flip_files=nil
  #make a flip xfm
  if symmetric 
    flip_step=prefix+"_flip"
    flip_xfm=tmpdir+'flip.xfm'
    do_cmd('param2xfm','-scales',-1, 1, 1, flip_xfm,'-clobber') unless File.exist?(flip_xfm)
  end
  
  if symmetric
    flip_files=Array.new
    do_cmd('param2xfm','-scales',-1, 1, 1, tmpdir_w+'/flip.xfm','-clobber') unless File.exist?(tmpdir_w+'/flip.xfm')
    in_files.each do |file|
      fname=File::basename(file)
      output_file=tmpdir_w+fname+'.flip.mnc'
      logfile=log_dir+fname+'.flip.mnc.log'
      flip_files << output_file
      unless File.exist?(output_file)
        batch.submit(flip_step, '',logfile) do |c|
          if stagger
            delay=(rand*30).to_i
            c<<['sleep',delay]
          end
          c<<[bin_dir+'do_flip', file, output_file]
        end
      end
    end
  end #symmetric

  #add all files to the file list
  #in_files.push(*flip_files)
  mask_avg_list=tmpdir+'0mask_list.txt'
  
  # prestep build all subjects masks
  prev_step=prefix+"_mask"
  delay=0
  masks=Array.new
  #creating symlinks/unpacking...
  
  (0 .. (in_files.length()-1)).each do |i|
    file=in_files[i]
    mask=''
    mask=in_masks[i] unless in_masks.empty?
    
    fname=File::basename(file)
    #output_mask=tmpdir_w+fname+'.0'
    masks << mask unless mask.empty?
    logfile=log_dir+fname+'.0.log'

    if symmetric && !mask.empty?
      output_mask_flip=tmpdir_w+fname+'.0.flip_mask.mnc'
      masks << output_mask_flip
      unless File.exist?(output_mask_flip)
        batch.submit(prev_step,flip_step ,logfile) do |c| 
          if stagger
            delay=(rand*30).to_i
            c<<['sleep',delay]
          end
          c<<[bin_dir+'do_flip',mask,output_mask_flip]
        end
      end
    end
  end 
  
  write_list(masks,mask_avg_list) if !in_masks.empty? && avg_mask

  cleanup_list=Array.new
  cleanup_list_good=Array.new
  step5_name=''
  it_name=''
  prev_it_name=''
  it_dir=''
  prev_it_dir=''
  weights=''
  it=0
  (0 .. fit_steps.size()-1).each do |f|
    fit=fit_steps[f]
    iterations=fit_iter[f]
    non_linear_on=(fit>0)
    step=fit
    puts "Fitting:#{fit} Nonlinear:#{non_linear_on} Step: #{step} Iterations: #{iterations}"
    (1..iterations).each do |iti|
      it+=1
      puts it
      it_name=sprintf("%02d",it)
      prev_it_name=sprintf("%02d",it-1)
      it_dir=tmpdir+it_name+'/'
      prev_it_dir=tmpdir+prev_it_name+'/'
      FileUtils.mkdir_p it_dir
      
      if symmetric 
        # copy flipping xfm into each directory
        # just a way to satisfy symmetric processing scripts
        FileUtils.cp flip_xfm,it_dir 
      end
      log_dir=it_dir
      #check if the average already exists, if it does - move on to next stage
      next_model=tmpdir+"avg_"+it_name+".mnc"
      if File.exist?(next_model)
        puts "Found #{next_model}, skipping!"
        next
      end
      if it>1
        cur_model     =tmpdir+"avg_"+prev_it_name+".mnc"    
        cur_model_mask=tmpdir+"avg_"+prev_it_name+"_mask.mnc" 
      else
        cur_model_mask=tmpdir+"avg_"+prev_it_name+"_mask.mnc" if cur_model_mask.nil? || cur_model_mask.empty?
      end
      xfm_list=Array.new
      xfm_i_list=Array.new
      
      # remove files from the previous iteration
      #0 build target mask, if needed
      step0_name=prefix+"m_"+it_name
      logfile=log_dir+"avg_"+prev_it_name+"_mask.mnc.log"
      
      unless File.exist?(cur_model_mask) || in_masks.empty?
        batch.submit(step0_name, prev_step, logfile) do |e|
           if symmetric
             e << [bin_dir+'do_avg_sym_mask',mask_avg_list,cur_model_mask]
           else
            if bandwidth > 0.0 && !weights.empty?
              e << [bin_dir+'do_w_avg_mask',mask_avg_list,weights,cur_model_mask]
            else
              e << [bin_dir+'do_avg_mask',mask_avg_list,cur_model_mask]
            end
           end
        end
        prev_step=step0_name
      end
      
      unless cleanup_list_good.empty?
        step6_name=prefix+"cg_"+it_name
        clean_list_good=tmpdir+"clean_good_"+it_name+".lst"
        write_list(cleanup_list_good,clean_list_good)
        batch.submit(step6_name, prev_step, log_dir+step6_name+'.log') do |e|
          e<<[bin_dir+'do_check_cleanup',cur_model,clean_list_good]
        end
        prev_step=step6_name
      end

      cleanup_list.clear()
      cleanup_list_good.clear()
      #cleanup_list_good<<cur_model_mask
      
      #1 register to a model
      step1_name=prefix+"reg_"+it_name
      delay=0
      file_mask=''
      (0 .. (in_files.length()-1)).each do |ff|
        file=in_files[ff]
        file_mask=in_masks[ff] unless in_masks.empty?
        
        fname=File::basename(file)
        output_base=it_dir+fname+'.'+it_name
        output=output_base+".xfm"
        output_grid=output_base+"_grid_0.mnc"
        output_i=output_base+".i.xfm"
        output_i_grid=output_base+".i_grid_0.mnc"
        output_flip_flip=output_base+"_flip_flip.xfm"
        
        prev_xfm='';
        if it>1
          prev_xfm=prev_it_dir+fname+'.'+prev_it_name+".corr.xfm"
        end
        fliped=tmpdir_w+fname+'.flip.mnc'
        fliped_mask=tmpdir_w+fname+'.0.flip_mask.mnc'
        logfile=log_dir+fname+'.'+it_name+'.xfm.log'
        #output for the next stage
        output_minc=output_base+'.mnc'
        unless (File.exist?(output) && File.exist?(output_i) ) || File.exists?(output_minc) 
          batch.submit(step1_name, prev_step,logfile) do |e|
            if stagger
              delay=(rand*30).to_i
              e<<['sleep',delay]
            end
            
            unless disable_linear && non_linear_on
              if symmetric
                e << [bin_dir+'do_sym_linear_registration',file, fliped, cur_model, 
                  file_mask, fliped_mask, cur_model_mask, output, output_i,output_i+'.flip.xfm']
                cleanup_list << output_i+'.flip.xfm'
                xfm_i_list << output_i+'.flip.xfm'
              else  
                e << [bin_dir+'do_linear_registration', file  , cur_model, 
                    file_mask, cur_model_mask,output,output_i]
              end
            else
              if prev_xfm.empty?
                prev_xfm='none'
              end
              
              if symmetric
                
                e<<[bin_dir+'do_sym_nonlinear_registration', file,fliped, cur_model, 
                    file_mask,fliped_mask, 
                    cur_model_mask,step,prev_xfm,
                    output,output_i,output_i+'.flip.xfm']
                    
                cleanup_list << output_i+'.flip.xfm'
                cleanup_list << output_i+'.flip_grid_0.mnc'
                xfm_i_list << output_i+'.flip.xfm'
              else  
                if log_euclidian
                e << [bin_dir+'do_nonlinear_registration_log', file, 
                      cur_model, file_mask, cur_model_mask, 
                      step, prev_xfm, output, output_i]
                else
                e << [bin_dir+'do_nonlinear_registration', file, 
                      cur_model, file_mask, cur_model_mask, 
                      step, prev_xfm, output, output_i]
                end
              end
              #this will be produced by xfmavg
              cleanup_list << output_grid
            end
          end
        end
        cleanup_list << output
        xfm_list << output
        cleanup_list << output_i
        xfm_i_list << output_i
      end
     
      #2 xfm average
      step2_name=prefix+"avg_"+it_name
      xfm_avg=it_dir+"avg_"+it_name+".xfm"
      #workaround
      xfm_avg_list=it_dir+"avg_"+it_name+".lst"
      write_list(xfm_i_list,xfm_avg_list)
      cleanup_list << xfm_avg_list
      xfm_avg_i=it_dir+"avg_i_"+it_name+".xfm"
      weights=it_dir+"weights_"+it_name+".lst"
      logfile=log_dir+"avg_i_"+it_name+".xfm.log"
      
      batch.submit(step2_name, step1_name,logfile) do |e|
        if bandwidth > 0.0
          e<<[bin_dir+'do_xfm_w_avg', xfm_avg_list, xfm_avg, bandwidth, weights]
        else
          if log_euclidian
            e<<[bin_dir+'do_xfm_avg_log',  xfm_avg_list, xfm_avg]
          else
            e<<[bin_dir+'do_xfm_avg',  xfm_avg_list, xfm_avg]
          end
        end
      end
      
      #3 concatenate xfm and do resampling
      step3_name=prefix+"res_"+it_name
      minc_list=Array.new
      xfm_i_list=Array.new
      masks=Array.new
      mask_avg_list=it_dir+'mask_list.'+it_name
      delay=0
      file_mask=''
      (0 .. (in_files.length()-1)).each do |ff|
        file=in_files[ff]
        file_mask=in_masks[ff] unless in_masks.empty?
        
        fname=File.basename(file)
        output_base=it_dir+fname+'.'+it_name
        fliped=it_dir+fname+'.flip.mnc'
        input=output_base+".xfm"
        input_flip=output_base+".flip.xfm"
        output=output_base+".corr.xfm"
        output_flip=output_base+".flip.corr.xfm"
        output_minc=output_base+".mnc"
        output_flip_minc=output_base+".flip.mnc"

        output_mask=output_base+"_mask.mnc"
        output_flip_mask=output_base+"_mask.flip.mnc"

        logfile=log_dir+fname+'.'+it_name+'.mnc.log'
        
        fliped_mask=tmpdir_w+fname+'.0.flip_mask.mnc'
        
        unless File.exist?(output_minc) && File.exist?(file_mask) && (File.exists?(output_flip_minc) ||  !symmetric )
          batch.submit(step3_name, step2_name,logfile) do |e|
            if stagger
              delay=(rand*30).to_i
              e<<['sleep',delay]
            end
            resample_script='do_concat_resample'
            if spline 
              resample_script='do_concat_resample_itk'
            end
            if symmetric
              e<<[bin_dir+resample_script,input,file,xfm_avg,
                 cur_model,file_mask, output,output_minc,output_mask,output_flip_minc]
            else
              e<<[bin_dir+resample_script,input,file,xfm_avg,
                 cur_model,file_mask, output,output_minc,output_mask]
            end
          end
        end
        minc_list << output_minc
        unless keep_xfms
          cleanup_list_good << output << output_base+".corr_grid_1.mnc"<< output_base+".corr_grid_0.mnc"
        end
        cleanup_list_good << output_minc << output_mask
        masks << output_mask
        if symmetric
          cleanup_list_good << output_flip << output_flip_minc << output_base+".flip.corr_grid_1.mnc"<< output_base+".flip.corr_grid_0.mnc"
          minc_list << output_flip_minc
        end #symmetric
      end
      write_list(masks,mask_avg_list) if avg_mask
      #4 average outputs, make a new model 
      step4_name=prefix+"avg_minc_"+it_name
      cur_model=next_model #tmpdir+"avg_"+it.to_s+".mnc"

      cur_sd=tmpdir+"sd_"+it_name+".mnc"
      cur_asym=it_dir+"asym_"+it_name+".mnc"
      cur_sym=it_dir+"sym_"+it_name+".xfm"
      cur_sym_grid=it_dir+"sym_"+it_name+"_grid_0.xfm"
      mnc_avg_list=it_dir+'avg_list_'+it_name+'.lst'
      write_list(minc_list,mnc_avg_list)
      cleanup_list_good << mask_avg_list
      batch.submit(step4_name, step3_name, log_dir+"avg_"+it_name+'.log') do |e|
        if bandwidth>0
          e<<[bin_dir+'do_w_minc_average',mnc_avg_list,weights,cur_model]
        elsif patches>0 
          e<<[bin_dir+'do_patch_average',patches,mnc_avg_list,cur_model,cur_sd]
        else
          e<<[bin_dir+'do_minc_average',mnc_avg_list,cur_model,cur_sd]
        end
      end
      #5 cleanup ?
      step5_name=prefix+"clean_"+it_name
      clean_list=it_dir+"clean_"+it_name+".lst"
      write_list(cleanup_list,clean_list)
      batch.submit(step5_name, step4_name, log_dir+step5_name+'.log') do |e|
        e<<[bin_dir+'do_check_cleanup',cur_model,clean_list]
      end
      prev_step=step5_name
    end
  end
  
  #calculate the last model mask 
  cur_model=tmpdir+"avg_"+it_name+".mnc" 
  cur_model_mask=tmpdir+"avg_"+it_name+"_mask.mnc" 
  step0_name=prefix+"m_"+it_name
  #0 build target mask, if needed
  logfile=log_dir+"avg_"+it_name+"_mask.mnc.log"
  unless File.exist?(cur_model_mask)
    batch.submit(step0_name, prev_step, logfile) do |e|
       if avg_mask
         if symmetric
           e<< [bin_dir+'do_avg_sym_mask',mask_avg_list,cur_model_mask]
         else
          if bandwidth>0
            e<< [bin_dir+'do_w_avg_mask',mask_avg_list,weights,cur_model_mask]
          else
            e<< [bin_dir+'do_avg_mask',mask_avg_list,cur_model_mask]
          end
         end
       else
        if bet
          e<< [bin_dir+'do_bet_mask',cur_model,cur_model_mask]
        else
          #extract the whole head + neiborhood
          e<< [bin_dir+'do_simple_mask',cur_model,cur_model_mask]
        end
       end
    end
  end
rescue RuntimeError => e
  STDERR.puts e
  exit 1  
end