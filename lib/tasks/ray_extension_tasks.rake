namespace :ray do

  require "fileutils"
  require "open-uri"
  require "yaml"

  @p = "vendor/extensions"
  @r = "#{@p}/ray"
  @c = "#{@r}/config"

  namespace :extension do
    desc "Install an extension."
    task :install do
      messages = [
        "================================================================================",
        "AN EXTENSION NAME IS REQUIRED! For example:",
        "rake ray:extension:install name=extension_name"
      ]
      require_options = [ENV["name"]]
      validate_command(messages, require_options)
      install_extension
    end
    desc "Search available extensions."
    task :search do
      messages = [
        "================================================================================",
        "A SEARCH TERM IS REQUIRED! For example:",
        "rake ray:extension:search term=search_term"
      ]
      require_options = [ENV["term"]]
      validate_command(messages, require_options)
      search_extensions(show = true)
    end
    desc "Disable an extension."
    task :disable do
      messages = [
        "================================================================================",
        "AN EXTENSION NAME IS REQUIRED! For example,",
        "rake ray:extension:disable name=extension_name"
      ]
      require_options = [ENV["name"]]
      validate_command(messages, require_options)
      disable_extension
    end
    desc "Enable an extension."
    task :enable do
      messages = [
        "================================================================================",
        "AN EXTENSION NAME IS REQUIRED! For example:",
        "rake ray:extension:enable name=extension_name"
      ]
      require_options = [ENV["name"]]
      validate_command(messages, require_options)
      enable_extension
    end
    desc "Uninstall an extension"
    task :uninstall do
      messages = [
        "================================================================================",
        "AN EXTENSION NAME IS REQUIRED! For example:",
        "rake ray:extension:uninstall name=extension_name"
      ]
      require_options = [ENV["name"]]
      validate_command(messages, require_options)
      uninstall_extension
    end
    desc "Update existing remotes on an extension."
    task :pull do
      require_git
      pull_remote
    end
    desc "Setup a new remote on an extension."
    task :remote do
      require_git
      messages = [
        "================================================================================",
        "AN EXTENSION NAME AND GITHUB USERNAME ARE REQUIRED! For example:",
        "rake ray:extension:remote name=extension_name hub=user_name"
      ]
      require_options = [ENV["name"], ENV["hub"]]
      validate_command(messages, require_options)
      add_remote
    end
    desc "Install an extension bundle."
    task :bundle do
      install_bundle
    end
    desc "View all available extensions."
    task :all do
      search_extensions(show = true)
    end
    desc "Update an extension."
    task :update do
      update_extension
    end
  end

  namespace :setup do
    desc "Set server auto-restart preference."
    task :restart do
      messages = [
        "================================================================================",
        "A SERVER TYPE IS REQUIRED! For example:",
        "rake ray:setup:restart server=mongrel_cluster",
        "rake ray:setup:restart server=passenger"
      ]
      require_options = [ENV["server"]]
      validate_command(messages, require_options)
      set_restart_preference
    end
    desc "Set extension download preference."
    task :download do
      set_download_preference
    end
  end

  namespace :help do
    desc "Show Ray shortcuts."
    task :shortcuts do
      puts("rake ray:i name=x # install")
      puts("rake ray:d name=x # disable")
      puts("rake ray:e name=x # enable")
      puts("rake ray:s term=x # search")
    end
  end

  # i've gotten progressively lazier
  task :ext => ["extension:install"]
  task :search => ["extension:search"]
  task :dis => ["extension:disable"]
  task :en => ["extension:enable"]
  task :i => ["extension:install"]
  task :s => ["extension:search"]
  task :d => ["extension:disable"]
  task :e => ["extension:enable"]

end

def install_extension
  get_download_preference
  search_extensions(show = nil)
  determine_install_path # cancels installation if extension exists
  replace_github_username if ENV["hub"]
  if ENV["lib"]
    @gem_dependencies = [ENV["lib"]]
    install_dependencies
  end
  git_extension_install if @download == "git"
  http_extension_install if @download == "http"
  check_submodules
  check_dependencies
  run_extension_tasks
  messages = [
    "================================================================================",
    "The #{@name} extension has been installed successfully."
  ]
  output(messages)
  restart_server
end

def disable_extension
  @name = ENV["name"]
  move_to_disabled
  messages = [
    "================================================================================",
    "The #{@name} extension has been disabled.",
    "You can re-enable it later by running:",
    "rake ray:extension:enable name=#{@name}"
  ]
  output(messages)
  restart_server
end

def enable_extension
  name = ENV["name"]
  if File.exist?("#{@p}/#{name}")
    remove_dir("#{@p}/.disabled/#{name}")
    messages = [
      "================================================================================",
      "The #{name} extension was re-installed after it was disabled.",
      "So there is no reason to re-enable the version you previously disabled.",
      "I removed the duplicate, disabled copy of the extension."
    ]
    output(messages)
    exit
  end
  if File.exist?("#{@p}/.disabled/#{name}")
    FileUtils.mv("#{@p}/.disabled/#{name}", "#{@p}/#{name}")
    messages = [
      "================================================================================",
      "The #{name} extension has been enabled",
      "You can disable it again later by running:",
      "rake ray:extension:disable name=#{name}"
    ]
    output(messages)
  else
    messages = [
      "================================================================================",
      "The #{name} extension is not disabled.",
      "If you were trying to install the extension try running:",
      "rake ray:extension:install name=#{name}"
    ]
    output(messages)
    exit
  end
  restart_server
end

def update_extension
  name = ENV["name"] if ENV["name"]
  # update all extensions, except ray
  if name == "all"
    get_download_preference
    extensions = Dir.entries(@p) - [".", "..", ".DS_Store", ".disabled", "ray"]
    if @download == "git"
      extensions.each do |name|
        git_extension_update(name)
      end
    elsif @download == "http"
      extensions.each do |name|
        http_extension_update(name)
      end
    else
      messages = [
        "================================================================================",
        "Your download preference is broken, to repair it run:",
        "rake ray:setup:download"
      ]
      output(messages)
      exit
    end
  # update a single extension
  elsif name
    get_download_preference
    if @download == "git"
      git_extension_update(name)
    elsif @download == "http"
      http_extension_update(name)
    else
      messages = [
        "================================================================================",
        "Your download preference is broken, to repair it run:",
        "rake ray:setup:download"
      ]
      output(messages)
      exit
    end
  # update ray
  else
    name = "ray"
    get_download_preference
    if @download == "git"
      git_extension_update(name)
    elsif @download == "http"
      messages = [
        "================================================================================",
        "Ray can only update itself with git."
      ]
      output(messages)
      exit
    else
      messages = [
        "================================================================================",
        "Your download preference is broken, to repair it run:",
        "rake ray:setup:download"
      ]
      output(messages)
      exit
    end
  end
end

def install_bundle
  unless File.exist?("config/extensions.yml")
    messages = [
      "================================================================================",
      "You don't seem to have a bundle file available.",
      "Refer to the documentation for more information on extension bundles.",
      "http://wiki.github.com/johnmuhl/radiant-ray-extension/usage#ext-bundle"
    ]
    output(messages)
    exit
  end
  File.open("config/extensions.yml") do |bundle|
    # load up a yaml file and send the contents back into ray for installation
    YAML.load_documents(bundle) do |extension|
      for i in 0...extension.length do
        name = extension[i]["name"]
        options = []
        options << " hub=" + extension[i]["hub"] if extension[i]["hub"]
        options << " lib=" + extension[i]["lib"] if extension[i]["lib"]
        sh("rake ray:extension:install name=#{name}#{options}")
        begin
          extension[i]["remote"].length
        rescue Exception
          messages = [
            "================================================================================",
            "Your extensions.yml file is using Ray 1.x features no longer in Ray 2.",
            "Refer to the wiki for upgrade information, http://is.gd/jV5h"
          ]
          output(messages)
          exit
        end
        if extension[i]["remote"].length > 0
          for j in 0...extension[i]["remote"].length
            sh("rake ray:extension:remote name=#{name} hub=#{extension[i]["remote"][j]}")
          end
          sh("rake ray:extension:pull name=#{name}")
        end
      end
    end
  end
end

def git_extension_install
  @url.gsub!(/http/, "git")
  # check if the user is cloning their own repo and switch to ssh
  # use public=true to force the public url to be used on your own repos
  unless ENV["public"]
    home = `echo ~`.gsub!("\n", "")
    if File.exist?("#{home}/.gitconfig")
      File.readlines("#{home}/.gitconfig").map do |f|
        line = f.rstrip
        if line.include?("user = ")
          me = line.gsub(/\tuser\ =\ /, "")
          origin = @url.gsub(/git:\/\/github.com\/(.*)\/.*/, "\\1")
          @url.gsub!(/git:\/\/github.com\/(.*\/.*)/, "git@github.com:\\1") if me == origin
        end
      end
    end
  end
  if File.exist?(".git/HEAD")
    sh("git submodule add #{@url}.git #{@p}/#{@name}")
  else
    sh("git clone #{@url}.git #{@p}/#{@name}")
  end
end

def http_extension_install
  FileUtils.makedirs("#{@r}/tmp")
  begin
    tarball = open("#{@url}/tarball/master", "User-Agent" => "open-uri").read
  rescue Exception
    messages = [
      "================================================================================",
      "GitHub failed to serve the requested extension archive.",
      "These are usually temporary issues, just try it again."
    ]
    output(messages)
    exit
  end
  open("#{@r}/tmp/#{@name}.tar.gz", "wb") { |f| f.write(tarball) }
  Dir.chdir("#{@r}/tmp") do
    begin
      sh("tar xzvf #{@name}.tar.gz")
    rescue Exception
      rm("#{@name}.tar.gz")
      messages = [
        "================================================================================",
        "The #{@name} extension archive is not decompressing properly.",
        "You can usually fix this by simply running the command again."
      ]
      output(messages)
      exit
    end
    rm("#{@name}.tar.gz")
  end
  sh("mv #{@r}/tmp/* #{@p}/#{@name}")
  remove_dir("#{@r}/tmp")
end

def git_extension_update(name)
  puts("================================================================================")
  Dir.chdir("#{@p}/#{name}") do
    sh("git checkout master")
    sh("git pull origin master")
    messages = ["The #{name} extension has been updated."]
    output(messages)
  end
end

def http_extension_update(name)
  puts("================================================================================")
  Dir.chdir("#{@p}/#{name}") do
    sh("rake ray:extension:disable name=#{name}")
    sh("rake ray:extension:install name=#{name}")
    remove_dir("#{@r}/disabled_extensions/#{name}")
    messages = ["The #{name} extension has been updated."]
    output(messages)
  end
end

def check_dependencies
  if File.exist?("#{@p}/#{@name}/dependency.yml")
    @extension_dependencies = []
    @gem_dependencies       = []
    @plugin_dependencies    = []
    File.open("#{@p}/#{@name}/dependency.yml").map do |f|
      YAML.load_documents(f) do |dependency|
        for i in 0...dependency.length
          @extension_dependencies << dependency[i]["extension"] if dependency[i].include?("extension")
          @gem_dependencies << dependency[i]["gem"] if dependency[i].include?("gem")
          @plugin_dependencies << dependency[i]["plugin"] if dependency[i].include?("plugin")
        end
      end
    end
    install_dependencies
  end
end

def check_submodules
  if File.exist?("#{@p}/#{@name}/.gitmodules")
    submodule_urls = []
    submodule_paths = []
    File.readlines("#{@p}/#{@name}/.gitmodules").map do |f|
      line = f.rstrip
      submodule_urls << line.gsub(/\turl\ =\ /, "") if line.include? "url = "
      submodule_paths << line.gsub(/\tpath\ =\ /, "") if line.include? "path = "
    end
    install_submodules(submodule_urls, submodule_paths)
  end
end

def install_dependencies
  if @extension_dependencies.length > 0
    @extension_dependencies.each { |e| system "rake ray:extension:install name=#{e}" }
  end
  if @gem_dependencies.length > 0
    gem_sources = `gem sources`.split("\n")
    gem_sources.each { |g| @github = g if g.include?("github") }
    sh("gem sources --add http://gems.github.com") unless @github
    @gem_dependencies.each do |g|
      has_gem = `gem list #{g}`.strip
      if has_gem.length == 0
        messages = [
          "The #{@name} extension requires one or more gems.",
          "YOU MAY BE PROMPTED FOR YOU SYSTEM ADMINISTRATOR PASSWORD!"
        ]
        output(messages)
        sh("sudo gem install #{g}")
      end
    end
  end
  if @plugin_dependencies.length > 0
    messages = [
      "================================================================================",
      "Plugin dependencies are not supported by Ray, use git submodules instead.",
      "If you're not the extension author consider contacting them about this issue."
    ]
    output(messages)
    @plugin_dependencies.each do |p|
      messages = [
        "The #{@name} extension requires the #{p} plugin.",
        "Please install the #{p} plugin manually."
      ]
      output(messages)
    end
  end
end

def install_submodules(submodule_urls, submodule_paths)
  if @download == "git"
    if File.exist?(".git/HEAD")
      submodule_urls.each do |url|
        Dir.chdir("#{@p}/#{@name}") do
          sh("git submodule init")
          sh("git submodule update")
        end
      end
    else
      submodule_urls.each do |url|
        Dir.chdir("#{@p}/#{@name}") do
          sh("git submodule init")
          sh("git submodule update")
        end
      end
    end
  elsif @download == "http"
    submodule_urls.each do |url|
      FileUtils.makedirs("#{@r}/tmp")
      submodule.gsub!(/(git:)(\/\/github.com\/.*\/.*)(.git)/, "http:\\2/tarball/master")
      tarball = open("#{url}", "User-Agent" => "open-uri").read
      submodule.gsub!(/http:\/\/github.com\/.*\/(.*)\/tarball\/master/, "\\1")
      open("#{@r}/tmp/#{url}.tar.gz", "wb") { |f| f.write(tarball) }
      Dir.chdir("#{@r}/tmp") do
        begin
          sh("tar xzvf #{url}.tar.gz")
        rescue Exception
          rm("#{url}.tar.gz")
          messages = [
            "================================================================================",
            "GitHub failed to serve the requested archive.",
            "These issues are usually temporary, just try again."
          ]
          output(messages)
          exit
        end
        rm("#{url}.tar.gz")
      end
      sh("mv #{@r}/tmp/* #{@p}/#{@name}/#{submodule_paths[submodule_urls.index(url)]}")
      remove_dir("#{@r}/tmp")
    end
  else
    messages = [
      "================================================================================",
      "Your download preference is broken, to repair it run:.",
      "rake ray:setup:download"
    ]
    output(messages)
    exit
  end
end

def run_extension_tasks
  if File.exist?("#{@p}/#{@name}/lib/tasks")
    rake_files = Dir.entries("#{@p}/#{@name}/lib/tasks") - [".", ".."]
    if rake_files.length == 1
      rake_file = rake_files[0]
    else
      rake_files.each do |f|
        rake_file = f if f.include?("_extension_tasks.rake")
      end
    end
    tasks = []
    File.readlines("#{@p}/#{@name}/lib/tasks/#{rake_file}").map do |f|
      line = f.rstrip
      tasks << "install" if line.include? "task :install =>"
      tasks << "migrate" if line.include? "task :migrate =>"
      tasks << "update" if line.include? "task :update =>"
    end
    unless tasks.empty?
      if ENV['RAILS_ENV']
        env = ENV['RAILS_ENV']
      else
        env = "development"
      end
      if @uninstall
        if tasks.include?("uninstall")
          begin
            sh("rake #{env} radiant:extensions:#{@name}:uninstall")
            puts("Successfully uninstalled")
          rescue Exception
            messages = [
              "================================================================================",
              "The #{@name} extension failed to uninstall properly.",
              "You can uninstall the extension manually by running:",
              "rake #{env} radiant:extensions:#{@name}:migrate VERSION=0",
              "and then removing any associated files and directories."
            ]
            output(messages)
            exit
          end
        else
          if tasks.include?("migrate")
            begin
              sh("rake #{env} radiant:extensions:#{@name}:migrate VERSION=0")
              puts("Successfully migrated to VERSION=0")
            rescue Exception
              messages = [
                "================================================================================",
                "The #{@name} extension failed to uninstall properly.",
                "You can uninstall the extension manually by running:",
                "rake radiant:extensions:#{@name}:migrate VERSION=0",
                "and then removing any associated files and directories."
              ]
              output(messages)
              exit
            end
          end
          # do a simple search to find files to remove, misses are frequent
          if tasks.include?("update")
            require "find"
            files = []
            Find.find("#{@p}/#{@name}/public") { |file| files << file }
            files.each do |f|
              if f.include?(".")
                unless f.include?(".DS_Store")
                  file = f.gsub(/#{@p}\/#{@name}\/public/, "public")
                  FileUtils.rm("#{file}", :force => true)
                end
              end
            end
            messages = [
              "I tried to delete assets associated with the #{@name} extension,",
              "but may have missed some while trying not to delete anything accidentally.",
              "You may want manually clean up your public directory after an uninstall."
            ]
            output(messages)
          end
        end
      else
        if tasks.include?("install")
          begin
            sh("rake #{env} radiant:extensions:#{@name}:install")
          rescue Exception => error
            cause = "install"
            quarantine_extension(cause)
          end
        else
          if tasks.include?("migrate")
            begin
              sh("rake #{env} radiant:extensions:#{@name}:migrate")
            rescue Exception => error
              cause = "migrate"
              quarantine_extension(cause)
            end
          end
          if tasks.include?("update")
            begin
              sh("rake #{env} radiant:extensions:#{@name}:update")
            rescue Exception => error
              cause = "update"
              quarantine_extension(cause)
            end
          end
        end
      end
    end
    puts("No tasks to run") if tasks.empty?
    if @uninstall
      if tasks.include?("uninstall")
        begin
          sh("rake radiant:extensions:#{@name}:uninstall")
        rescue Exception => error
          cause = "uninstall"
          quarantine_extension(cause)
        end
      else
        if tasks.include?("migrate")
          begin
            sh("rake radiant:extensions:#{@name}:migrate VERSION=0")
          rescue Exception => error
            cause = "migrate"
            quarantine_extension(cause)
          end
        end
        if tasks.include?("update")
          require "find"
          files = []
          Find.find("#{@p}/#{@name}/public") { |file| files << file }
          files.each do |f|
            if f.include?(".")
              unless f.include?(".DS_Store")
                file = f.gsub(/#{@p}\/#{@name}\/public/, "public")
                FileUtils.rm("#{file}", :force => true)
              end
            end
          end
          messages = [
            "I tried to delete assets associated with the #{@name} extension,",
            "but may have missed some while trying not to delete anything accidentally.",
            "You may want manually clean up your public directory after an uninstall."
          ]
          output(messages)
        end
      end
    else
    end
  else
    puts("The #{@name} extension has no task file.")
  end
end

def uninstall_extension
  @uninstall = true
  @name = ENV["name"].gsub(/-/, "_")
  unless File.exist?("#{@p}/#{@name}")
    messages = [
      "================================================================================",
      "The #{@name} extension is not installed."
    ]
    output(messages)
    exit
  end
  run_extension_tasks
  FileUtils.makedirs("#{@r}/tmp")
  FileUtils.mv("#{@p}/#{@name}", "#{@r}/tmp/#{@name}")
  remove_dir("#{@r}/tmp")
  messages = [
    "================================================================================",
    "The #{@name} extension has been uninstalled."
  ]
  output(messages)
end

def search_extensions(show)
  check_search_freshness
  name = ENV["name"] if ENV["name"]
  term = ENV["term"] if ENV["term"]
  extensions = []
  authors = []
  urls = []
  descriptions = []
  File.open("#{@r}/search.yml") do |repositories|
    YAML.load_documents(repositories) do |repository|
      for i in 0...repository["repositories"].length
        e = repository["repositories"][i]["name"]
        if name or term
          d = repository["repositories"][i]["description"]
          if name
            term = name
          elsif term
            name = term
          end
          if e.include?(term) or e.include?(name) or d.include?(term) or d.include?(name)
            extensions << e
            authors << repository["repositories"][i]["owner"]
            urls << repository["repositories"][i]["url"]
            descriptions << d
          end
        else
          extensions << e
          authors << repository["repositories"][i]["owner"]
          urls << repository["repositories"][i]["url"]
          descriptions << repository["repositories"][i]["description"]
        end
      end
    end
  end
  if show
    show_search_results(term, extensions, authors, urls, descriptions)
  else
    choose_extension_to_install(name, extensions, authors, urls, descriptions)
  end
end

def show_search_results(term, extensions, authors, urls, descriptions)
  puts("================================================================================")
  if extensions.length == 0
    messages = ["Your search term '#{term}' did not match any extensions."]
    output(messages)
    exit
  end
  for i in 0...extensions.length
    extension = extensions[i].gsub(/radiant-/, "").gsub(/-extension/, "")
    if descriptions[i].length >= 63
      description = descriptions[i][0..63] + "..."
    elsif descriptions[i].length == 0
      description = "(no description provided)"
    else
      description = descriptions[i]
    end
    messages = [
      "  extension: #{extension}",
      "     author: #{authors[i]}",
      "description: #{description}",
      "    command: rake ray:extension:install name=#{extension}"
    ]
    output(messages)
  end
  exit
end

def choose_extension_to_install(name, extensions, authors, urls, descriptions)
  if extensions.length == 1
    @url = urls[0]
    return
  end
  if extensions.include?(name) or extensions.include?("radiant-#{name}-extension")
    extensions.each do |e|
      e.gsub!(/radiant[-|_]/, "").gsub!(/[-|_]extension/, "")
      @url = urls[extensions.index(e)]
      break if e == name
    end
  else
    messages = [
      "I couldn't find an extension named '#{@search_name}'.",
      "The following is a list of extensions that might be related.",
      "Use the command listed to install the appropriate extension."
    ]
    output(messages)
    show_search_results(term = name, extensions, authors, urls, descriptions)
  end
end

def get_download_preference
  begin
    File.open("#{@c}/download.txt", "r") { |f| @download = f.gets.strip! }
  rescue
    set_download_preference
  end
  unless @download == "git" or @download == "http"
    messages = [
      "================================================================================",
      "Your download preference is broken, to repair it run one of:",
      "NOTE: `mongrel` and `thin` must be running as daemons",
      "rake ray:setup:restart server=mongrel_cluster",
      "rake ray:setup:restart server=passenger",
      "rake ray:setup:restart server=mongrel",
      "rake ray:setup:restart server=thin",
    ]
    output(messages)
    exit
  end
end

def set_download_preference
  FileUtils.makedirs("#{@c}")
  begin
    sh("git --version")
    @download = "git"
  rescue Exception
    @download = "http"
  end
  File.open("#{@c}/download.txt", "w") { |f| f.puts(@download) }
  messages = [
    "================================================================================",
    "Your download preference has been set to #{@download}."
  ]
  output(messages)
end

def set_restart_preference
  FileUtils.makedirs("#{@c}")
  supported_servers = ["mongrel_cluster", "mongrel", "passenger", "thin"]
  preference = ENV["server"]
  if supported_servers.include?(preference)
    File.open("#{@c}/restart.txt", "w") {|f| f.puts(preference)}
    messages = [
      "================================================================================",
      "Your restart preference has been set to #{preference}."
    ]
    output(messages)
    exit
  else
    messages = [
      "================================================================================",
      "I don't know how to restart #{preference}.",
      "Only Mongrel clusters and Phusion Passenger are currently supported.",
      "Run one of the following commands:",
      "NOTE: `mongrel` and `thin` must be running as daemons",
      "rake ray:setup:restart server=mongrel_cluster",
      "rake ray:setup:restart server=passenger",
      "rake ray:setup:restart server=mongrel",
      "rake ray:setup:restart server=thin"
      
    ]
    output(messages)
    exit
  end
end

def validate_command(messages, require_options)
  require_options.each do |option|
    unless option
      output(messages)
      exit
    end
  end
end

def output(messages)
  messages.each { |m| puts "#{m}" }
  puts("================================================================================")
  messages = []
end

def replace_github_username
  @url.gsub!(/(http:\/\/github.com\/).*(\/.*)/, "\\1#{ENV["hub"]}\\2")
end

def determine_install_path
  FileUtils.makedirs("#{@r}/tmp")
  # download an html list of the repository contents
  begin
    html = open("#{@url}.git", "User-Agent" => "open-uri").read
  rescue OpenURI::HTTPError
    messages = [
      "================================================================================",
      "GitHub is having trouble serving the request, just try it again."
    ]
    output(messages)
    exit
  end
  open("#{@r}/tmp/#{ENV["name"]}.html", "w") { |f| f.write(html) }
  # inspect the html list to determine the install path
  name = []
  File.readlines("#{@p}/ray/tmp/#{ENV["name"]}.html").map do |f|
    line = f.rstrip
    name << line if line.include?("_extension.rb")
  end
  @name = name[0].to_s
  @name.strip!.gsub!(/<li> <a href=".*">/, "").gsub!(/<\/a> <\/li>/, "").gsub!(/_extension.rb/, "")
  remove_dir("#{@r}/tmp")
  check_for_existing_installation
end

def check_for_existing_installation
  if File.exist?("#{@p}/#{@name}")
    messages = [
      "================================================================================",
      "The #{@name} extension is already installed."
    ]
    output(messages)
    exit
  end
end

def move_to_disabled
  FileUtils.makedirs("#{@p}/.disabled")
  if File.exist?("#{@p}/#{@name}")
    if File.exist?("#{@p}/.disabled/#{@name}")
      remove_dir("#{@p}/.disabled/#{@name}")
    end
    FileUtils.mv("#{@p}/#{@name}", "#{@p}/.disabled/#{@name}")
  else
    messages = [
      "================================================================================",
      "The #{@name} extension is not installed."
    ]
    output(messages)
    exit
  end
end

def quarantine_extension(cause)
  move_to_disabled
  messages = [
    "================================================================================",
    "The #{@name} extension failed to install properly.",
    "Specifically, the failure was caused by the extension's #{cause} task:",
    "Run `rake radiant:extensions:#{@name}:#{cause} --trace` for more details.",
    "The extension has been disabled and placed in #{@p}/.disabled"
  ]
  output(messages)
  exit
end

def require_git
  get_download_preference
  unless @download == "git"
    messages = [
      "================================================================================",
      "THIS COMMANDS REQUIRES GIT!",
      "Refer to http://git-scm.com/ for installation instructions."
    ]
    output(messages)
    exit
  end
end

def restart_server
  begin
    File.open("#{@c}/restart.txt", "r") { |f| @server = f.gets.strip! }
  rescue
    messages = [
      "Setup a restart preference if you'd like your server automatically restarted.",
      "Run the command corresponding to your application server:",
      "NOTE: `mongrel` and `thin` must be running as daemons",
      "rake ray:setup:restart server=mongrel_cluster",
      "rake ray:setup:restart server=passenger",
      "rake ray:setup:restart server=mongrel",
      "rake ray:setup:restart server=thin",
      "================================================================================",
      "YOU NEED TO RESTART YOUR SERVER!"
    ]
    output(messages)
    exit
  end
  if @server == "passenger"
    FileUtils.makedirs("tmp")
    FileUtils.touch("tmp/restart.txt")
    puts("Passenger restarted.")
  elsif @server == "mongrel_cluster"
    sh("mongrel_rails cluster::restart")
    puts("Mongrel cluster restarted.")
  elsif @server == "mongrel"
    sh("mongrel_rails restart")
    puts("Mongrel has been restarted")
  elsif @server == "thin"
    sh("thin restart")
    puts("Thin has been restarted")
  else
    messages = [
      "================================================================================",
      "Your restart preference is broken, to repair it run one of:",
      "rake ray:setup:restart server=mongrel_cluster",
      "rake ray:setup:restart server=passenger"
    ]
    output(messages)
  end
end

def add_remote
  hub = ENV["hub"]
  search_extensions(show = nil)
  @url.gsub!(/(http)(:\/\/github.com\/).*(\/.*)/, "git\\2" + hub + "\\3")
  extension = ENV['name']
  if File.exist?("#{@p}/#{extension}/.git")
    Dir.chdir("#{@p}/#{extension}") do
      sh("git remote add #{hub} #{@url}.git")
      sh("git fetch #{hub}")
      branches = `git branch -a`.split("\n")
      @new_branch = []
      branches.each do |branch|
        branch.strip!
        @new_branch << branch if branch.include?(hub)
        @current_branch = branch.gsub!(/\*\ /, "") if branch.include?("* ")
      end
      @new_branch.each do |branch|
        sh("git fetch #{hub} #{branch.gsub(/.*\/(.*)/, "\\1")}")
        sh("git checkout --track -b #{branch} #{branch}")
        sh("git checkout #{@current_branch}")
      end
    end
    messages = [
      "================================================================================",
      "All of #{hub}'s branches have been pulled into local branches.",
      "Use your normal git workflow to inspect and merge these branches."
    ]
    output(messages)
    exit
  else
    messages = [
      "================================================================================",
      "#{@p}/#{extension} is not a git repository."
    ]
    output(messages)
    exit
  end
end

def pull_remote
  name = ENV["name"] if ENV[ "name" ]
  if name
    @pull_branch = []
    Dir.chdir("#{@p}/#{name}") do
      if File.exist?(".git")
        branches = `git branch`.split("\n")
        branches.each do |branch|
          branch.strip!
          @pull_branch << branch if branch.include?("/")
          @current_branch = branch.gsub!(/\*\ /, "") if branch.include?("* ")
        end
        @pull_branch.each do |branch|
          sh("git checkout #{branch}")
          sh("git pull #{branch.gsub(/(.*)\/.*/, "\\1")} #{branch.gsub(/.*\/(.*)/, "\\1")}")
          sh("git checkout #{@current_branch}")
        end
      else
        messages = [
          "================================================================================",
          "#{@p}/#{name} is not a git repository."
        ]
        output(messages)
        exit
      end
      messages = [
        "================================================================================",
        "Updated all remote branches of the #{name} extension.",
        "Use your normal git workflow to inspect and merge these branches."
      ]
      output(messages)
      exit
    end
  else
    extensions = @name ? @name.gsub(/\-/, "_") : Dir.entries(@p) - [".", "..", ".DS_Store", ".disabled", "ray"]
    extensions.each do |extension|
      Dir.chdir("#{@p}/#{extension}") do
        if File.exist?(".git")
          @pull_branch = []
          branches = `git branch`.split("\n")
          branches.each do |branch|
            branch.strip!
            @pull_branch << branch if branch.include?("/")
            @current_branch = branch.gsub!(/\*\ /, "") if branch.include?("* ")
          end
          if @pull_branch.length > 0
            @pull_branch.each do |branch|
              sh("git checkout #{branch}")
              sh("git pull #{branch.gsub(/(.*)\/.*/, "\\1")} #{branch.gsub(/.*\/(.*)/, "\\1")}")
              sh("git checkout #{@current_branch}")
              messages = [
                "================================================================================",
                "Updated remote branches for the #{extension} extension."
              ]
              output(messages)
            end
          end
        else
          messages = [
            "================================================================================",
            "#{@p}/#{extension} is not a git repository."
          ]
          output(messages)
        end
      end
    end
    messages = [
      "================================================================================",
      "Updated all remote branches.",
      "Use your normal git workflow to inspect and merge these branches."
    ]
    output(messages)
    exit
  end
end

def check_search_freshness
  if File.exist?("#{@r}/search.yml")
    mod_time = File.mtime("#{@r}/search.yml")
    if mod_time < Time.now - (60 * 60 * 24 * 2)
      download_search_file
    end
  else
    download_search_file
  end
end

def download_search_file
  begin
    search = open("http://github.com/johnmuhl/radiant-ray-extension/raw/master/search.yml", "User-Agent" => "open-uri").read
  rescue Exception
    messages = [
      "================================================================================",
      "GitHub failed to serve the requested search file.",
      "These are usually temporary issues, just try it again."
    ]
    output(messages)
    exit
  end
  open("#{@r}/search.yml", "wb") { |f| f.write(search) }
  messages = ["Search file updated."]
  output(messages)
end

namespace :radiant do
  namespace :extensions do
    namespace :ray do
      task :migrate do
        puts("Ray doesn't have any migrate tasks to run.")
      end
      task :update do
        puts("Ray doesn't have any static assets to copy.")
      end
    end
  end
end
