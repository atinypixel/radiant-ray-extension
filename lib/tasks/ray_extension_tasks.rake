namespace :ray do
  require 'ftools'
  require 'yaml'

  @path = "vendor/extensions"
  @ray  = "#{@path}/ray"
  @conf = "#{@ray}/config"

  namespace :extension do
    task :install do
      messages = ["The install command requires an extension name.", "rake ray:extension:install name=extension_name"]
      require_options = [ENV['name']]
      install_extension(messages, require_options)
    end
    task :search do
      messages = ["The search command requires a search term.", "rake ray:extension:search term=search_term"]
      require_options = [ENV['term']]
      validate_command(messages, require_options)
      search_extensions
      search_results
    end
    task :disable do
      name = ENV['name']
      messages = ["The disable command requires an extension name.", "rake ray:extension:disable name=extension_name"]
      require_options = [ENV['name']]
      validate_command(messages, require_options)
      disable_extension(name)
    end
    task :enable do
      name = ENV['name']
      messages = ["The enable command requires an extension name.", "rake ray:extension:enable name=extension_name"]
      require_options = [ENV['name']]
      validate_command(messages, require_options)
      enable_extension
    end
    desc "Uninstall an extension"
    task :uninstall do
      messages = ["The remove command requires an extension name.", "rake ray:extension:remove name=extension_name"]
      require_options = [ENV['name']]
      validate_command(messages, require_options)
      uninstall_extension
    end
    desc "Update existing remotes on an extension."
    task :pull do
      pull_remote
    end
    desc "Setup a new remote on an extension."
    task :remote do
      messages = ["The remote command requires an extension name and a GitHub username.", "rake ray:extension:remote name=extension_name hub=user_name"]
      require_options = [ENV['name'], ENV['hub']]
      add_remote(messages, require_options)
    end
    desc "Install an extension bundle."
    task :bundle do
      install_bundle
    end
    desc "View all available extensions."
    task :all do
      search_extensions
      search_results
    end
    desc "Update an extension."
    task :update do
      update_extension
    end
  end

  namespace :setup do
    desc "Set server auto-restart preference."
    task :restart do
      messages = ["I need to know the type of server you'd like auto-restarted.", "rake ray:setup:restart server=mongrel", "rake ray:setup:restart server=passenger"]
      require_options = [ENV['server']]
      validate_command(messages, required_options)
      set_restart_preference
    end
    desc "Set extension download preference."
    task :download do
      set_download_preference
    end
  end

  desc "Install an extension."
  task :ext => ["extension:install"]
  desc "Disable an extension."
  task :dis => ["extension:disable"]
  desc "Enable an extension."
  task :en => ["extension:enable"]
  desc "Search available extensions."
  task :search => ["extension:search"]
end

def install_extension(messages, require_options)
  validate_command(messages, require_options)
  get_download_preference
  search_extensions
  choose_extension_to_install
  replace_github_username if ENV['hub']
  git_extension_install if @download == "git"
  http_extension_install if @download == "http"
  set_download_preference if @download != "git" and @download != "http"
  check_submodules
  check_dependencies
  validate_extension_location
  check_rake_tasks
  messages = ["The #{@name} extension has been installed successfully.", "Disable it with: rake ray:dis name=#{@name}"]
  output(messages)
  restart_server
end

def disable_extension(name)
  @name = name
  move_to_disabled
  messages = [
    "The #{@name} extension has been disabled. Enable it with:",
    "rake ray:extension:enable name=#{@name}"
  ]
  output(messages)
  restart_server
end

def enable_extension(name)
  if File.exist?("#{@path}/.disabled/#{name}")
    begin
      move("#{@path}/.disabled/#{name}", "#{@path}/#{name}")
    rescue Exception
      messages = ["You already have a copy of the #{name} extension installed."]
      output(messages)
      exit
    end
    messages = [
      "The #{name} extension has been enabled. Disable it with:",
      "rake ray:extension:disable name=#{name}"
    ]
    output(messages)
  else
    messages = [
      "The #{name} extension was not disabled by Ray. Install it with:",
      "rake ray:extension:install name=#{name}"
    ]
    output(messages)
    exit
  end
  restart_server
end

def update_extension
  name = ENV['name'] if ENV['name']
  # update all extensions, except ray
  if name == 'all'
    get_download_preference
    if @download == "git"
      extensions = Dir.entries(@path) - ['.', '.DS_Store', 'ray', '..']
      extensions.each do |extension|
        git_extension_update(extension)
      end
    elsif @download == "http"
      extensions = Dir.entries(@path) - ['.', '.DS_Store', 'ray', '..']
      extensions.each do |extension|
        http_extension_update(extension)
      end
    else
      messages = ["Your download preference is broken.", "Please run, `rake ray:setup:download` to repair it."]
      output(messages)
    end
  # update a single extension
  elsif name
    extension = name
    get_download_preference
    if @download == "git"
      git_extension_update(extension)
    elsif @download == "http"
      http_extension_update(extension)
    else
      messages = ["Your download preference is broken.", "Please run, `rake ray:setup:download` to repair it."]
      output(messages)
    end
  # update ray
  else
    extension = 'ray'
    get_download_preference
    if @download == "git"
      git_extension_update(extension)
    elsif @download == "http"
      puts("Ray can only update itself with git.")
    else
      messages = ["Your download preference is broken.", "Please run, `rake ray:setup:download` to repair it."]
      output(messages)
    end
  end
end

def install_bundle
  unless File.exist?('config/extensions.yml')
    messages = ["You don't seem to have a bundle file available.", "Refer to the documentation for more information on extension bundles.", "http://wiki.github.com/johnmuhl/radiant-ray-extension/usage#ext-bundle"]
    output(messages)
    exit
  end
  File.open('config/extensions.yml') do |bundle|
    # load up a yaml file and send the contents back into ray for installation
    YAML.load_documents(bundle) do |extension|
      for i in 0...extension.length do
        name = extension[i]['name']
        options = []
        options << " hub=" + extension[i]['hub'] if extension[i]['hub']
        options << " remote=" + extension[i]['remote'] if extension[i]['remote']
        options << " lib=" + extension[i]['lib'] if extension[i]['lib']
        sh("rake ray:extension:install name=#{name}#{options}")
      end
    end
  end
end

def git_extension_install
  @url.gsub!(/http/, 'git')
  # check if the user is cloning their own repo and switch to ssh
  unless ENV['public']
    home = `echo ~`.gsub!("\n", '')
    if File.exist?("#{home}/.gitconfig")
      File.readlines("#{home}/.gitconfig").map do |f|
        line = f.rstrip
        if line.include? 'user = '
          me = line.gsub(/\tuser\ =\ /, '')
          origin = @url.gsub(/git:\/\/github.com\/(.*)\/.*/, "\\1")
          @url.gsub!(/git:\/\/github.com\/(.*\/.*)/, "git@github.com:\\1") if me == origin
        end
      end
    end
  end
  if File.exist?('.git/HEAD')
    begin
      sh("git submodule add #{@url}.git #{@path}/#{@_name}")
    rescue Exception => err
      messages = [err]
      output(messages)
      exit
    end
  else
    begin
      sh("git clone #{@url}.git #{@path}/#{@_name}")
    rescue Exception => err
      messages = [err]
      output(messages)
      exit
    end
  end
end

def http_extension_install
  require 'open-uri'
  File.makedirs("#{@ray}/tmp")
  begin
    tarball = open("#{@url}/tarball/master", "User-Agent" => "open-uri").read
  rescue OpenURI::HTTPError
    messages = ["There was a glitch in the system and the extension could not be downloaded.", "These are usually temporary issues, just try it again."]
    output(messages)
    exit
  end
  open("#{@ray}/tmp/#{@_name}.tar.gz", "wb") {|f| f.write(tarball)}
  Dir.chdir("#{@ray}/tmp") do
    begin
      sh("tar xzvf #{@_name}.tar.gz")
    rescue Exception
      rm("#{@_name}.tar.gz")
      messages = ["The #{@_name} extension archive is not decompressing properly.", "You can usually fix this by simply running the command again."]
      output(messages)
      exit
    end
    rm("#{@_name}.tar.gz")
  end
  begin
    sh("mv #{@ray}/tmp/* #{@path}/#{@_name}")
  rescue
    messages = ["You already have the #{@_name} extension installed.", "If you're trying to update it, use the update command instead.", "rake ray:extension:update name=#{@_name}"]
    output(messages)
    rm_r("#{@ray}/tmp")
    exit
  end
  rm_r("#{@ray}/tmp")
end

def git_extension_update(extension)
  Dir.chdir("#{@path}/#{extension}") do
    sh("git checkout master")
    sh("git pull origin master")
  end
  puts("#{extension} extension updated.")
end

def http_extension_update(extension)
  Dir.chdir("#{@path}/#{extension}") do
    sh("rake ray:extension:disable name=#{extension}")
    sh("rake ray:extension:install name=#{extension}")
    rm_r("#{@ray}/disabled_extensions/#{extension}")
    puts("#{extension} extension updated.")
  end
end

def check_dependencies
  if File.exist?("#{@path}/#{@_name}/dependency.yml")
    @extension_dependencies = []
    @gem_dependencies = []
    @plugin_dependencies = []
    File.open("#{@path}/#{@_name}/dependency.yml" ) do |dependence|
      YAML.load_documents(dependence) do |dependency|
        total = dependency.length - 1
        for i in 0..total do
          @extension_dependencies << dependency[i]['extension'] if dependency[i].include?('extension')
          @gem_dependencies << dependency[i]['gem'] if dependency[i].include?('gem')
          @plugin_dependencies << dependency[i]['plugin'] if dependency[i].include?('plugin')
        end
      end
    end
    install_dependencies
  end
end

def check_submodules
  if File.exist?("#{@path}/#{@_name}/.gitmodules")
    submodules = []
    File.readlines("#{@path}/#{@_name}/.gitmodules").map do |f|
      line = f.rstrip
      submodules << line.gsub(/\turl\ =\ /, '') if line.include? 'url = '
    end
    install_submodules(submodules)
  end
end

def install_dependencies
  if @extension_dependencies.length > 0
    @extension_dependencies.each {|e| system "rake ray:extension:install name=#{e}"}
  end
  if @gem_dependencies.length > 0
    gem_sources = `gem sources`.split("\n")
    gem_sources.each {|g| @github = g if g.include?("github")}
    sh("gem sources --add http://gems.github.com") unless @github
    messages = ["The #{@name} extension requires one or more gems.", "YOU MAY BE PROMPTED FOR YOU SYSTEM ADMINISTRATOR PASSWORD!"]
    output(messages)
    @gem_dependencies.each do |g|
      has_gem = `gem list #{g}`.strip
      if has_gem.length == 0
        sh("sudo gem install #{g}")
      end
    end
  end
  if @plugin_dependencies.length > 0
    messages = [
      "Plugin dependencies are not supported by Ray.",
      "Consider adding plugins as git submodules, which are supported by Ray.",
      "If you're not the extension author consider contacting them about this issue."
    ]
    output(messages)
    @plugin_dependencies.each do |p|
      messages = [
        "The #{@name} extension requires the #{p} plugin,",
        "but Ray does not support plugin dependencies.",
        "Please install the #{p} plugin manually."
      ]
      output(messages)
    end
  end
end

def install_submodules(submodules)
  if @download == "git"
    if File.exist?('.git/HEAD')
      submodules.each do |submodule|
        sh("git submodule add #{submodule} vendor/plugins/#{submodule.gsub(/(git:\/\/github.com\/.*\/)(.*)(.git)/, "\\2")}")
      end
    else
      submodules.each do |submodule|
        sh("git clone #{submodule} vendor/plugins/#{submodule.gsub(/(git:\/\/github.com\/.*\/)(.*)(.git)/, "\\2")}")
      end
    end
  elsif @download == "http"
    submodules.each do |submodule|
      File.makedirs("#{@ray}/tmp")
      submodule.gsub!(/(git:)(\/\/github.com\/.*\/.*)(.git)/, "http:\\2/tarball/master")
      tarball = open("#{submodule}", "User-Agent" => "open-uri").read
      submodule.gsub!(/http:\/\/github.com\/.*\/(.*)\/tarball\/master/, "\\1")
      open("#{@ray}/tmp/#{submodule}.tar.gz", "wb") {|f| f.write(tarball)}
      Dir.chdir("#{@ray}/tmp") do
        begin
          sh("tar xzvf #{submodule}.tar.gz")
        rescue Exception
          rm("#{submodule}.tar.gz")
          messages = ["The #{submodule} extension archive is not decompressing properly.", "You can usually fix this by simply running the command again."]
          output(messages)
          exit
        end
        rm("#{submodule}.tar.gz")
      end
      sh("mv #{@ray}/tmp/* vendor/plugins/#{submodule}")
      rm_r("#{@ray}/tmp")
    end
  else
    messages = ["Your download preference is broken.", "Please run, `rake ray:setup:download` to repair it."]
    output(messages)
  end
end

def run_extension_tasks
  if File.exist?("#{@path}/#{@name}/lib/tasks")
    rake_files = Dir.entries("#{@path}/#{@name}/lib/tasks") - [".", ".."]
    if rake_files.length == 1
      rake_file = rake_files[0]
    else
      rake_files.each do |f|
        rake_file = f if f.include?("_extension_tasks.rake")
      end
    end
    tasks = []
    File.readlines("#{@path}/#{@name}/lib/tasks/#{rake_file}").map do |f|
      line = f.rstrip
      tasks << 'install' if line.include? 'task :install =>'
      tasks << 'migrate' if line.include? 'task :migrate =>'
      tasks << 'update' if line.include? 'task :update =>'
    end
    if tasks.include?('install')
      begin
        sh("rake radiant:extensions:#{@name}:install --trace")
      rescue Exception => error
        cause = "install"
        quarantine_extension(cause)
      end
    else
      if tasks.include?('migrate')
        begin
          sh("rake radiant:extensions:#{@name}:migrate --trace")
        rescue Exception => error
          cause = "migrate"
          quarantine_extension(cause)
        end
      end
      if tasks.include?('update')
        begin
          sh("rake radiant:extensions:#{@name}:update --trace")
        rescue Exception => error
          cause = "update"
          quarantine_extension(cause)
        end
      end
    end
  else
    puts "The #{@name} extension has no task file."
  end
end

def uninstall_extension
  @uninstall = true
  @name = ENV['name'].gsub(/-/, '_')
  unless File.exist?("#{@path}/#{@name}")
    messages = ["The #{@name} extension is not installed."]
    output(messages)
    exit
  end
  check_rake_tasks
  run_uninstall_tasks
  messages = ["The #{@name} extension has been uninstalled. To install it run:", "rake ray:ext name=#{@name}"]
  output(messages)
end

def run_uninstall_tasks
  if @tasks
    if @tasks.empty?
      puts("The #{@name} extension has no tasks to run.")
    else
      if @tasks.include?('uninstall')
        begin
          sh("rake #{RAILS_ENV} radiant:extensions:#{@name}:uninstall")
          puts('Uninstall task ran successfully.')
        rescue Exception
          messages = ["The #{@name} extension failed to uninstall properly.", "Please uninstall the extension manually.", "rake radiant:extensions:#{@name}:migrate VERSION=0", "Then remove any associated files and directories."]
          output(messages)
          exit
        end
      else
        if @tasks.include?('migrate')
          begin
            sh("rake #{RAILS_ENV} radiant:extensions:#{@name}:migrate VERSION=0")
            puts('Migrated to VERSION=0 successfully.')
          rescue Exception
            messages = ["The #{@name} extension failed to uninstall properly.", "Please uninstall the extension manually.", "rake radiant:extensions:#{@name}:migrate VERSION=0", "Then remove any associated files and directories."]
            output(messages)
            exit
          end
        end
        # do a simple search to find files to remove, misses are frequent
        if @tasks.include?('update')
          require 'find'
          files = []
          Find.find("#{@path}/#{@name}/public") {|file| files << file}
          files.each do |f|
            if f.include?('.')
              unless f.include?('.DS_Store')
                file = f.gsub(/#{@path}\/#{@name}\/public/, 'public')
                File.delete("#{file}") rescue nil
              end
            end
          end
          messages = ["I tried to delete assets associated with the #{@name} extension,", "but may have missed some while trying not to delete anything accidentally.", "You may want manually clean up your public directory after an uninstall."]
          output(messages)
        end
      end
    end
  end
  File.makedirs("#{@ray}/removed_extensions")
  move("#{@path}/#{@name}", "#{@ray}/removed_extensions/#{@name}")
  rm_r("#{@ray}/removed_extensions/#{@name}")
end

def search_extensions
  @_name = ENV['name'] if ENV['name']
  @_term = ENV['term'] if ENV['term']
  @extensions = []
  @authors = []
  @urls = []
  @descriptions = []
  if File.exist?("#{@ray}/search.yml")
    cached_search
  else
    online_search
  end
end

def cached_search
  File.open("#{@ray}/search.yml") do |repositories|
    YAML.load_documents(repositories) do |repository|
      for i in 0...repository['repositories'].length
        e = repository['repositories'][i]['name']
        if @_name or @_term
          d = repository['repositories'][i]['description']
          if @_name
            @_term = @_name
          elsif @_term
            @_name = @_term
          end
          if e.include?(@_term) or e.include?(@_name) or d.include?(@_term) or d.include?(@_name)
            @extensions << e
            @authors << repository['repositories'][i]['owner']
            @urls << repository['repositories'][i]['url']
            @descriptions << d
          end
        else
          @extensions << e
          @authors << repository['repositories'][i]['owner']
          @urls << repository['repositories'][i]['url']
          @descriptions << repository['repositories'][i]['description']
        end
      end
    end
  end
end

def online_search
  puts("Online searching is not implemented.") # TODO: implement online_search
  exit
end

def search_results
  if @extensions.length == 0
    messages = ["Your search term '#{@_term}' did not match any extensions."]
    output(messages)
    exit
  end
  for i in 0...@extensions.length
    extension = @extensions[i].gsub(/radiant-/, '').gsub(/-extension/, '')
    if @descriptions[i].length >= 63
      description = @descriptions[i][0..63] + '...'
    elsif @descriptions[i].length == 0
      description = "(no description provided)"
    else
      description = @descriptions[i]
    end
    messages = ["  extension: #{extension}\n     author: #{@authors[i]}\ndescription: #{description}\n    command: rake ray:ext name=#{extension}"]
    output(messages)
  end
  exit
end

def choose_extension_to_install
  if @extensions.length == 1
    @url = @urls[0]
    @extension = @url.gsub(/http:\/\/github.com\/.*\//, '').gsub(/radiant[-|_]/, '').gsub(/[-|_]extension/, '')
    return
  end
  if @extensions.include?(@_name) or @extensions.include?("radiant-#{@_name}-extension")
    @extensions.each do |e|
      @extension = e.gsub(/radiant[-|_]/, '').gsub(/[-|_]extension/, '')
      @url = @urls[@extensions.index(e)]
      break if @extension == @_name
    end
  else
    messages = ["I couldn't find an extension named '#{@_name}'.", "The following is a list of extensions that might be related.", "Use the command listed to install the appropriate extension."]
    output(messages)
    search_results
  end
end

def get_download_preference
  begin
    File.open("#{@conf}/download.txt", 'r') {|f| @download = f.gets.strip!}
  rescue
    set_download_preference
  end
end

def set_download_preference
  File.makedirs("#{@conf}")
  begin
    sh("git --version")
    @download = "git"
  rescue
    @download = "http"
  end
  File.open("#{@conf}/download.txt", 'w') {|f| f.puts(@download)}
  messages = ["Your download preference has been set to #{@download}."]
  output(messages)
end

def set_restart_preference
  File.makedirs("#{@conf}")
  preference = ENV['server']
  if preference == 'mongrel' or preference == 'passenger'
    File.open("#{@conf}/restart.txt", 'w') {|f| f.puts(preference)}
    messages = ["Your restart preference has been set to #{preference}.", "Now I'll auto-restart your server whenever necessary."]
    output(messages)
  else
    messages = "I don't know how to restart #{preference}.", "Only Mongrel clusters and Phusion Passenger are currently supported.", "Run one of the following commands:", "rake ray:setup:restart server=mongrel", "rake ray:setup:restart server=passenger"
    output(messages)
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
  puts "================================================================================"
  messages.each { |m| puts "#{m}" }
  puts "================================================================================"
  messages = []
end

def replace_github_username
  @url.gsub!(/(http:\/\/github.com\/).*(\/.*)/, "\\1#{ENV['hub']}\\2")
end

def validate_extension_location
  @name = @_name
  unless File.exist?("#{@path}/#{@_name}/#{@_name}_extension.rb")
    path = Regexp.escape(@path)
    begin
      sh("ls #{@path}/#{@_name}/*_extension.rb")
    rescue Exception
      rm_r("#{@ray}/disabled_extensions/#{@_name}") rescue nil
      move("#{@path}/#{@_name}", "#{@ray}/disabled_extensions/#{@_name}")
      messages = ["#{@path}/#{@_name} is not a Radiant extension.", "It has been moved to #{@ray}/disabled_extensions/#{@_name}."]
      output(messages)
      exit
    end
    vendor_name = `ls #{@path}/#{@_name}/*_extension.rb`.gsub(/#{path}\/#{@_name}\//, "").gsub(/_extension.rb/, "").gsub(/\n/, "") rescue nil
    move_extension(vendor_name)
  end
end

def move_extension(vendor_name)
  begin
    move("#{@path}/#{@_name}", "#{@path}/#{vendor_name}")
  rescue
    messages = ["You already have the #{@_name} extension installed.", "If you're trying to update it, use the update command instead.", "rake ray:extension:update name=#{@_name}"]
    output(messages)
    rm_r("#{@path}/#{@_name}")
    exit
  end
  @name = vendor_name
end

def move_to_disabled
  File.makedirs("#{@path}/.disabled")
  if File.exist?("#{@path}/#{@name}")
    begin
      move("#{@path}/#{@name}", "#{@path}/.disabled/#{@name}")
    rescue Exception => error
      rm_r("#{@path}/.disabled/#{@name}")
      move("#{@path}/#{@name}", "#{@path}/.disabled/#{@name}")
    end
  else
    messages = [
      "The #{@name} extension is not installed. Install it with:",
      "rake ray:extension:install name=#{@name}"
    ]
    output(messages)
  end
end

def quarantine_extension(cause)
  move_to_disabled
  messages = [
        "The #{@name} extension failed to install properly.",
        "Specifically, the failure was caused by the extension's #{cause} task:",
        "Run `rake radiant:extensions:#{@name}:#{cause} --trace` for more details.",
        "The extension has been disabled and placed in #{@path}/.disabled"
  ]
  output(messages)
  exit
end

def require_git
  get_download_preference
  unless @download == "git"
    messages = ["This commands requires git.", "Refer to http://git-scm.com/ for installation instructions."]
    output(messages)
    exit
  end
end

def restart_server
  begin
    File.open("#{@conf}/restart.txt", 'r') {|f| @server = f.gets.strip!}
  rescue
    messages = ["You need to restart your server or set a restart preference.", "rake ray:setup:restart server=mongrel\nrake ray:setup:restart server=passenger"]
    output(messages)
    exit
  end
  if @server == "passenger"
    File.makedirs('tmp')
    File.open('tmp/restart.txt', 'w') {|f|}
    puts('Passenger restarted.')
  elsif @server == "mongrel"
    sh('mongrel_rails cluster::restart')
    puts('Mongrel cluster restarted.')
  else
    messages = ["Your restart preference is broken. Use the appropriate command to repair it.", "rake ray:setup:restart server=mongrel", "rake ray:setup:restart server=passenger"]
    output(messages)
  end
end

def add_remote(messages, require_options)
  validate_command(messages, require_options)
  require_git
  hub = ENV['hub']
  search_extensions
  choose_extension_to_install
  # fix up @url and @extension for this use
  @url.gsub!(/(http)(:\/\/github.com\/).*(\/.*)/, "git\\2" + hub + "\\3")
  @extension.gsub!(/-/, '_')
  if File.exist?("#{@path}/#{@extension}/.git")
    Dir.chdir("#{@path}/#{@extension}") do
      sh("git remote add #{hub} #{@url}.git")
      sh("git fetch #{hub}")
      # find new remote's branches
      branches = `git branch -a`.split("\n")
      @new_branch = []
      branches.each do |branch|
        branch.strip!
        @new_branch << branch if branch.include?(hub)
        @current_branch = branch.gsub!(/\*\ /, '') if branch.include?('* ')
      end
      # checkout user's branches
      @new_branch.each do |branch|
        sh("git fetch #{hub} #{branch.gsub(/.*\/(.*)/, "\\1")}")
        sh("git checkout --track -b #{branch} #{branch}")
        sh("git checkout #{@current_branch}")
      end
    end
    messages = ["All of #{hub}'s branches have been pulled into local branches.", "Use your normal git workflow to inspect and merge these branches."]
    output(messages)
  else
    messages = ["#{@path}/#{@extension} is not a git repository."]
    output(messages)
    exit
  end
end

def pull_remote
  require_git
  name = ENV['name'] if ENV[ 'name' ]
  # pull remotes on a single extension
  if name
    @pull_branch = []
    Dir.chdir("#{@path}/#{name}") do
      if File.exist?(".git")
        branches = `git branch`.split("\n")
        branches.each do |branch|
          branch.strip!
          @pull_branch << branch if branch.include?('/')
          @current_branch = branch.gsub!(/\*\ /, '') if branch.include?('* ')
        end
        @pull_branch.each do |branch|
          sh("git checkout #{branch}")
          sh("git pull #{branch.gsub(/(.*)\/.*/, "\\1")} #{branch.gsub(/.*\/(.*)/, "\\1")}")
          sh("git checkout #{@current_branch}")
        end
      else
        messages = ["#{@path}/#{name} is not a git repository."]
        output(messages)
        exit
      end
      messages = ["Updated all remote branches of the #{name} extension.", "Use your normal git workflow to inspect and merge these branches."]
      output(messages)
    end
  # pull remotes on all extensions with remotes
  else
    extensions = @name ? @name.gsub(/\-/, '_') : Dir.entries(@path) - ['.', '.DS_Store', '..', 'ray']
    extensions.each do |extension|
      Dir.chdir("#{@path}/#{extension}") do
        if File.exist?(".git")
          @pull_branch = []
          branches = `git branch`.split("\n")
          branches.each do |branch|
            branch.strip!
            @pull_branch << branch if branch.include?('/')
            @current_branch = branch.gsub!(/\*\ /, '') if branch.include?('* ')
          end
          if @pull_branch.length > 0
            @pull_branch.each do |branch|
              sh("git checkout #{branch}")
              sh("git pull #{branch.gsub(/(.*)\/.*/, "\\1")} #{branch.gsub(/.*\/(.*)/, "\\1")}")
              sh("git checkout #{@current_branch}")
              messages = ["Updated remote branches for the #{extension} extension."]
              output(messages)
            end
          end
        else
          messages = ["#{@path}/#{extension} is not a git repository."]
          output(messages)
        end
      end
    end
    # messages = ["Use your normal git workflow to inspect and merge branches."]
    # output(messages)
  end
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
