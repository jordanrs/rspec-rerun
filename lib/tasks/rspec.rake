require 'rspec/core/rake_task'
require 'nokogiri'

xml_output_path = 'coverage/junit' 

desc "Run RSpec code examples."
task "rspec-rerun:spec", :retry_count do |t, args|
  retry_count = (args[:retry_count] || ENV['RSPEC_RERUN_RETRY_COUNT'] || 1).to_i
  @runcount = 0
  @xml_output = args[:xml_output] || false

  fail "retry count must be >= 1" if retry_count <= 0
  FileUtils.rm_f RSpec::Rerun::Formatters::FailuresFormatter::FILENAME

  Dir.glob("#{xml_output_path}/retry*.xml").each { |f| File.delete(f) }

  Rake::Task["rspec-rerun:run"].execute
  while !$?.success? && retry_count > 0
    retry_count -= 1
    @runcount += 1
    failed_count = File.read(RSpec::Rerun::Formatters::FailuresFormatter::FILENAME).split(/\n+/).count
    msg = "[#{Time.now}] Failed, re-running #{failed_count} failure#{failed_count == 1 ? '' : 's'}"
    msg += ", #{retry_count} #{retry_count == 1 ? 'retry' : 'retries'} left" if retry_count > 0
    $stderr.puts "#{msg} ..."
    Rake::Task["rspec-rerun:rerun"].execute
  end
  Rake::Task["rspec-rerun:xml-merge"].execute
  if !$?.success?
    failed_count = File.read(RSpec::Rerun::Formatters::FailuresFormatter::FILENAME).split(/\n+/).count
    $stderr.puts "[#{Time.now}] #{failed_count} failure#{failed_count == 1 ? '' : 's'}."
    fail "#{failed_count} failure#{failed_count == 1 ? '' : 's'}"
  end
end

desc "Run RSpec examples."
RSpec::Core::RakeTask.new("rspec-rerun:run") do |t|
  t.pattern = ENV['RSPEC_RERUN_PATTERN'] if ENV['RSPEC_RERUN_PATTERN']
  t.fail_on_error = false
  t.rspec_opts = [
    "--require", File.join(File.dirname(__FILE__), '../rspec-rerun'),
    "--format", "RSpec::Rerun::Formatters::FailuresFormatter",
    "--require", "yarjuf",
    "-f", "JUnit", "-o", "coverage/junit/first.xml",
    File.exist?(".rspec") ? File.read(".rspec").split(/\n+/).map { |l| l.shellsplit } : nil
  ].flatten
end

desc "Re-run failed RSpec examples."
RSpec::Core::RakeTask.new("rspec-rerun:rerun") do |t|
  t.pattern = ENV['RSPEC_RERUN_PATTERN'] if ENV['RSPEC_RERUN_PATTERN']
  t.fail_on_error = false
  t.rspec_opts = [
    "-O", RSpec::Rerun::Formatters::FailuresFormatter::FILENAME,
    "--require", File.join(File.dirname(__FILE__), '../rspec-rerun'),
    "--format", "RSpec::Rerun::Formatters::FailuresFormatter",
    "--require", "yarjuf",
    "-f", "JUnit", "-o", "coverage/junit/retry-#{@runcount}.xml",
    File.exist?(".rspec") ? File.read(".rspec").split(/\n+/).map { |l| l.shellsplit } : nil
  ].flatten
end


desc "Merge junit reports"
task "rspec-rerun:xml-merge" do
  results = Nokogiri::XML::Document.parse(File.open("#{xml_output_path}/first.xml"))
  Dir.glob("#{xml_output_path}/retry*.xml").each do |f|  
    retries = Nokogiri::XML::Document.parse(File.open(f))
    retries.xpath("testsuites/testsuite/testcase").each do |node|
      original = results.xpath("testsuites/testsuite/testcase[@name='#{node.attribute('name')}']").first
      original.replace(node)
    end

  end
  
  File.open("#{xml_output_path}/results.xml", 'w') {|f| f.write(results) }
end
