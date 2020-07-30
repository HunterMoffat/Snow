
## runs facter after deployment

after_activity :__deployment__ do |nodes|
    execute_many "apt-get update -y", :idempotent => true
    execute_many "apt-get install -y facter", :idempotent => true
    facts = execute_many "facter --yaml", :idempotent => true
    # TODO: collect the facts later or something

    data = engine.inline_process(facts) do |fs|
        forall fs do |f|
            yaml = (stdout_of f)
            node = (node_of f)
            value [ node, yaml ]
        end
    end

    facter_facts = { }
    data.each do |node, yaml|
        puts yaml
        facts = YAML.load(yaml)
        facter_facts[node] = facts
    end
    run :"__getset__.set", :facter_facts, facter_facts
end

activity :get_fact do |node, factname|
    facts = run :"__getset__.get", :facter_facts
    facts[node][factname.to_s]
end
