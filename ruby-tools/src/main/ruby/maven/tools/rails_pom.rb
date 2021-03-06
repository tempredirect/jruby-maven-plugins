require File.join(File.dirname(__FILE__), 'model.rb')
require File.join(File.dirname(__FILE__), 'gemfile_reader.rb')

module Maven
  module Tools
    class RailsPom

      def initialize(args = {})
        @versions = { :jetty_plugin => "7.1.0.RC1",
                       :jruby_complete => "1.5.3",
                       :jruby_rack => "1.0.4.dev-SNAPSHOT",
                       :jruby_plugins => "0.22.0",
                       :war_plugin => "2.1",
                     }.merge(args)
      end

      def check_rails(file)
        raise "it is not rails" unless File.exists?(File.join(File.dirname(file.to_s), "config", "application.rb"))
      end

      def plugin_version(group, name)
        if name =~ /\./
          names = [name.to_s]
        else
          names = ["org.apache.maven.plugins.maven-#{name}-plugin",
                   "de.saumya.mojo.#{name}-maven-plugin", "#{name}"]
        end
        group.each do |dep|
          if dep.type == :plugin
            names.each do |n|
              if dep[0].to_s == n
                return dep[1]
              end
            end
          end
        end
        @versions["#{name}_plugin".to_sym]
      end

      def version(group, name)
        group.each do |dep|
          if dep[0].to_s == name.to_s
            return dep[1]
          end
        end
      end

      def create_pom(file, filename = nil)
        if file.is_a? File
          check_rails(file) 
          name = File.basename(File.dirname(File.expand_path(file.path)))
          gemfile = GemfileReader.new(File.read(file.path))
        else
          gemfile = GemfileReader.new(file)
          file = File.new(filename) if filename
          name = File.basename(File.expand_path("."))
        end

        groups = gemfile.groups.dup
        groups[:production] ||= gemfile.group(:production)
        groups[:test] ||= gemfile.group(:test)
        groups[:development] ||= gemfile.group(:development)
        default = groups.delete(:default)

        GemProject.new(name) do |proj|
          proj.name = "#{name} - rails application"
          proj.packaging = "war"
          
          proj.repositories do |repos|
            repos.new("rubygems-releases") do |r|
              r.url = "http://gems.saumya.de/releases"
            end
            if version(default, "org.jruby.rack.jruby-rack") || @versions[:jruby_rack] =~ /SNAPSHOT/
              repos.new("saumya") do |saumya|
                saumya.url = "http://mojo.saumya.de/"
                saumya.releases(:enabled => false)
                saumya.snapshots(:enabled => true, :updatePolicy => :never)
              end
            end
            if (default.properties["jruby.plugins.version"] || @versions[:jruby_plugins]) =~ /SNAPSHOT/
              repos.new("sonatype-nexus-snapshots") do |nexus|
                nexus.url = "http://oss.sonatype.org/content/repositories/snapshots"
                nexus.releases(:enabled => false)
                nexus.snapshots(:enabled => true)
              end
            end
          end

          proj.dependencies do |deps|
            # allow to set version on jruby_rack and jruby_complete in Gemfile
            jruby_rack = false
            jruby_complete = false
            default.each do |dep|
              if [:gem,:jar].member? dep.type
                deps << dep
                jruby_rack = true if dep[0] == "org.jruby.rack.jruby-rack"
                jruby_complete = true if dep[0] == "org.jruby.jruby-complete"
              end
            end
            # use defaults version for missing dependencies
            deps << ["org.jruby.rack.jruby-rack", @versions[:jruby_rack]] unless jruby_rack
            deps << ["org.jruby.jruby-complete", @versions[:jruby_complete]] unless jruby_complete
          end
          
          proj.profiles.get(:development).default_activation
          proj.profiles.get(:production) do |prod|
            prod.properties = { 
              "gem.home" => "${project.build.directory}/rubygems-production", 
              "gem.path" => "${project.build.directory}/rubygems-production" 
            }.merge(groups[:production].properties)
          end
             
          groups.each do |n, g|
            unless [:run, :war].member? n
              proj.profiles.get(n.to_s) do |profile|
                profile.activation("rails.env", n.to_s)
                g.each do |gem|
                  if [:gem,:jar].member? gem.type
                    profile.dependencies << gem
                  end
                end
                new_plugins = g.select do |dep|
                  dep.type == :plugin
                end
                if new_plugins.size > 0
                  profile.build.plugins do |plugins|
                    new_plugins.each do |pl|
                    plugins.add(*pl)
                    end
                  end
                end
              end
            end
          end
          
          proj.properties = {
            "project.build.sourceEncoding" => "UTF-8", 
            "gem.home" => "${project.build.directory}/rubygems", 
            "gem.path" => "${project.build.directory}/rubygems", 
            "jruby.plugins.version" => "#{@versions[:jruby_plugins]}", 
            "jetty.version" => "#{@versions[:jetty_plugin]}",
            "rails.env" => "development"
          }.merge(default.properties)

          proj.build.plugins do |plugins|
            default.each do |dep|
              if dep.type == :plugin
                plugin = plugins.add(*dep)
              end
            end
           #  plugins.get_jruby(:gem) do |gem| 
#               gem.extensions = true
#               gem.executions.get("gemfile")do |gemfile|

#                 gemfile.configuration = {
#                   :script => 
# <<-EOF

# 		require 'fileutils'
# 		web_inf = File.join('${project.build.directory}', '${project.build.finalName}', 'WEB-INF')
# 		FileUtils.mkdir_p(web_inf)
# 		FileUtils.cp('Gemfile', File.join(web_inf, 'Gemfile'))
# EOF
#                 }
#               end
#               gemfile.phase = 'prepare-package'
#               gemfile.goals << 'exec'
#             end
            plugins.get(:rails3, plugin_version(default, :rails3) || @versions[:jruby_plugins]) do |rails|
              rails.extensions = true
              rails.executions.get(:initialize) do |e|
                e.goals = ["initialize"]
              end
            end
            plugins.add(:war, plugin_version(default, :war)) do |war|
              war.configuration = {
                :webResources => NamedArray.new(:resource) do |l|
                  l << { :directory => "public" }
                  l << { 
                    :directory => ".",
                    :targetPath => "WEB-INF",
                    :includes => ['app/**', 'config/**', 'lib/**', 'vendor/**', 'Gemfile']
                  }
                  l << {
                    :directory => '${gem.path}',
                    :targetPath => 'WEB-INF/gems'
                  }
                end
              }
            end
            if gemfile.phases.size > 0
              gemfile.phases.each do |name, v|
                plugins.get(:gem, plugin_version(default, :gem) || @versions[:jruby_plugins]) do |gem|
                  gem.executions.get("gemfile_#{name}") do |exec|
                    exec.phase = name
                    exec.goals = [:gemfile]
                    config = { :phase => name }
                    config[:gemfile] = file.path if file.is_a? File
                    exec.configuration = config
                  end
                end
              end
            end
          end
          proj.profiles.new(:war).build.plugins.add("org.mortbay.jetty.jetty-maven-plugin",
                                                    "${jetty.version}")
          proj.profiles.new(:run) do |run|
            run.default_activation
            run.build.plugins.add("org.mortbay.jetty.jetty-maven-plugin", 
                                  "${jetty.version}") do |jetty|
              jetty.configuration = {
                :webAppConfig => {
                  :overrideDescriptor => 'src/main/jetty/override-${rails.env}-web.xml'
                },
                # :systemProperties => {
                #   :systemProperty => {
                #     :name => 'bundle.gemfile',
                #     :value => 'Gemfile.maven'
                #   }
                # }
              }
            end
          end
        end
      end
    end
  end
end

if $0 == __FILE__
  pom = if ARGV[0].nil?
    Maven::Tools::RailsPom.new()
  else
    Maven::Tools::RailsPom.new(eval(ARGV[0]))
  end.create_pom(File.new("Gemfile"))
  puts pom.to_xml
end
