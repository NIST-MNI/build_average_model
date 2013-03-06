# SGE BATCH Ruby routines to execute processes using Sun Grig Engine
# Author::    Vladimir S. Fonov  
 
require 'tempfile'
require 'tmpdir'
require 'fileutils'

def do_cmd(*a)
  b=Array.new
  a.each{ |el| b << el.to_s()}
	if !system(*b)
    raise "DIED: #{a.join(' ')}"
	end
end

def do_batch(in_jobname, in_logfile, *a)
		IO.popen("qsub -N #{in_jobname} -o #{in_logfile} -j y -V -q wb221.q",'w') do |f| 
      f.puts '#! /bin/bash'
      f.puts 'hostname'
			f.puts a.join(' ')
		end
  if !$?.success? #process didn't succeeded
    raise "Batch submission #{jobname} failed!"
  end
end

def do_batch_q(in_jobname, in_logfile,in_q, *a)
  IO.popen("qsub -N #{in_jobname} -o #{in_logfile} -j y -V -q #{in_q}",'w') do |f| 
      f.puts '#! /bin/bash'
      f.puts 'hostname'
			f.puts a.join(' ')
		end
  if !$?.success? #process didn't succeeded
    raise "Batch submission #{jobname} failed!"
  end
end

def do_batch_dep(jobname, logfile, deps, q, *a)
  cmd="qsub -N #{jobname} -o #{logfile} -j y -V -q #{q}"
  cmd+=" -hold_jid "+deps.to_s unless deps.nil? || deps.to_s.empty?
  IO.popen(cmd,'w') do |f| 
      f.puts '#! /bin/bash'
      f.puts 'hostname'
			a.each do |x|
        if x.kind_of?(Array)
          f.puts "echo  "+x.join(' ')
          f.puts x.join(' ')
        else
          f.puts "echo  "+x.to_s
          f.puts x.to_s
        end
      end
		end
  if !$?.success? #process didn't succeeded
    raise "Batch submission #{jobname} failed!"
  end
end

class Qjob
  attr_writer :queue
  attr_writer :jobname
  attr_writer :deps
  attr_writer :logfile
  attr_writer :commands
  attr_writer :serial
  attr_writer :fake
  attr_writer :verbose
  
  #constructor
	def initialize(queue='wb221.q',logfile='',jobname='',deps='',serial=false,verbose=false)
		@queue=queue
    @jobname=jobname
    @deps=deps
    @logfile=logfile
    @commands=Array.new
    @serial=serial
    @fake=false
    @verbose=verbose
	end
  
  #execute given commands
  def submit
    unless @commands.empty? || @fake
      if @serial #run sequentially
        IO.popen("/bin/bash",'w') do |f| 
          @commands.each do |x|
            if x.kind_of?(Array)
              puts "cmd: #{x.join(' ')}" if @verbose 
              f.puts "echo  "+x.join(' ')# if @verbose
              f.puts x.join(' ')
            else
              f.puts "echo  \""+x.to_s+"\""# if @verbose
              f.puts x.to_s
              puts "cmd: #{x.to_s}" if @verbose 
            end
          end
        end
      else
        cmd="qsub  -j y -V -cwd -q #{@queue}"
        cmd+=" -N #{@jobname}"  unless @jobname.empty?
        cmd+=" -o #{@logfile} " unless @logfile.empty?
        cmd+=" -hold_jid "+@deps.to_s unless @deps.nil? || @deps.empty?
        puts "qsub: #{cmd}" if @verbose
        IO.popen(cmd,'w') do |f| 
            f.puts '#! /bin/bash'
            f.puts 'hostname'
            @commands.each do |x|
              if x.kind_of?(Array)
                puts "cmd: #{x.join(' ')}" if @verbose 
                f.puts "echo  "+x.join(' ')# if @verbose
                f.puts x.join(' ')
              else
                f.puts "echo  \""+x.to_s+"\""# if @verbose
                f.puts x.to_s
                puts "cmd: #{x.to_s}" if @verbose 
              end
            end
          end
        if !$?.success? #process didn't succeed
          raise "Batch submission #{@jobname} failed, job: #{$?.to_s} !"
        end
      end
    end
  end
  
  def << (c)
    @commands << c
    self
  end

  def clear
    @commands.clear
  end
  #will create Qjob object, yield , and then submit
  def Qjob.Execute(queue='wb221.q',logfile='',jobname='',deps='',serial=false,verbose=false)
    q=Qjob.new(queue,logfile,jobname,deps,serial,verbose)
      yield q
    q.submit
  end
end

class Batch
  attr_writer :queue
  attr_writer :serial
  attr_writer :fake
  attr_writer :verbose
  
	def initialize(queue='wb221.q',serial=false,verbose=false)
		@queue=queue
    @serial=serial
    @verbose=verbose
    @fake=false
	end
  
  def submit(jobname='',deps='',logfile='')
    Qjob.Execute(@queue,logfile,jobname,deps,@serial,@verbose) {|e| yield e}
  end
end

def check_file(in_file)
  if File.exist?(in_file)
    raise "File #{file} exists!"
  end
end

def makeTempFile(basename)
  tmp=Tempfile.new(basename)
  fn=tmp.path()
  tmp.close()
  return fn
end

def reportError(e)
  puts "An error occurred"
  puts "Error code: #{e.err}"
  puts "Error message: #{e.errstr}"
end


class TempDir
  attr_reader :path
  
  #constructor
	def initialize(prefix='',tmpdir='')
    tmpdir=Dir.tmpdir if tmpdir.empty?
    @path="#{tmpdir}/#{prefix}_#{(rand*10000).to_i}"
    while File.exist?(@path)
      @path="#{tmpdir}/#{prefix}_#{(rand*10000).to_i}"
    end
    FileUtils.mkdir_p(@path)
	end
 
  def to_s
    @path
  end
  
  def cleanup
    FileUtils.rm_rf(@path) unless @path.empty?
    @path=''
  end
end
