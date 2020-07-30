
# just reuse existing thing

def __check_g5k_credentials_path__
    home = Etc.getpwuid.dir
    return File.join(home, '.g5k.yaml')
end

def __check_g5k_credentials__
    path = __check_g5k_credentials_path__()
    if File.exist?(path)
        h = YAML.load_file(path)
        mode = File::Stat.new(path).mode
        raise "#{path} is accessible by other users" if (mode & 077 != 0)
    else
        return nil
    end
    if !h.is_a?(Hash) or h["user"].nil? or h["pass"].nil?
        raise "bad credentials"
    end
    [ h["user"], h["pass"] ]
end

def __save_g5k_credentials__
    path = __check_g5k_credentials_path__()
    File.open(path, "w") do |f|
        f.puts({
            "user" => $g5k_user,
            "pass" => $g5k_pass
        }.to_yaml)
    end
    File.chmod(0600, path)
end

$g5k_creds = __check_g5k_credentials__()

if $g5k_creds.nil?
    # no credentials
    $g5k_user = var(:g5k_user, :str, :text => "Provide G5K username: ")
    $g5k_pass = var(:g5k_pass, :pass, :text => "Provide G5K password: ")
    $g5k_save = var(:g5k_save, :bool, :callback => proc { |x| __save_g5k_credentials__ if x }, :text => "Do you want to save these credentials?")
else
    $g5k_user = set_var(:g5k_user, $g5k_creds.first)
    $g5k_pass = set_var(:g5k_pass, $g5k_creds.last)
end

# hide the password
set_var(:g5k_pass, "*" * $g5k_pass.length)

require 'xpflow/with_g5k'
