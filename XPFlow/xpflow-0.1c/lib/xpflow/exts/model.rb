
# this is pulled in by the main xpflow command line tool

# a standard model for an experiment

NODES_OPTS = { :doc => "Resource acquisition" }
DEPLOYMENT_OPTS = { :doc => "Deployment", :idempotent => true }
COLLECTION_OPTS = { :doc => "Collection of results" }
ANALYSIS_OPTS = { :doc => "Data analysis" }
EXPERIMENT_OPTS = { :doc => "Experiment" }
STANDARD_OPTS = { :doc => "Experiment model" }

$engine.process :__reservation__, NODES_OPTS do |nodes|
    value(nodes)
end

$engine.process :__deployment__, DEPLOYMENT_OPTS do |nodes|
    value(nodes)
end

$engine.process :__collection__, COLLECTION_OPTS do
    debug "Collecting results from nodes..."
    save_all_results
end

$engine.process :__analysis__, ANALYSIS_OPTS do |exp_result|
    value(exp_result)
end

$engine.activity :__install_node__, :doc => "Install a given node", :log_level => :none do |node|
    node.install()
end

$engine.process :__install_nodes__, :doc => "Initial node setup", :log_level => :none do |nodes|
    foreach nodes do |node|
        debug "Installing ", node
        run :__install_node__, node
    end
    count = (length_of nodes)
    on(count > 0) do
        bootstrap_taktuk(nodes)
    end
    # TODO: more parallel and more scalable
    forall nodes, :pool => 10 do |node|
        debug "Bootstrapping ", node
        code(node) { |node| node.bootstrap }
    end

    # checking nodes - run a simple command everywhere
    # be idempotent - if some nodes fail, retry them

    run :__check_nodes__, nodes
    value(nodes)
end

$engine.process :__check_nodes__, :doc => "Checking all nodes", :log_level => :none do |nodes|
    results = execute_many nodes, "true", :idempotent => true
    length = length_of results
    debug "All nodes (#{length}) checked"
end

$engine.activity :__fix_node_list__ do |list|
    (list.nil?) ? [] : list
end

$engine.process :__standard__, STANDARD_OPTS do |node_list|

    flattened_node_list = run :__fix_node_list__, node_list

    nodes = cache :__reservation__ do
        run :__reservation__, flattened_node_list
    end

    nodes_list = run :__install_nodes__, nodes

    # replace __reservation__ with a new set
    set_scope :__nodes__, nodes_list

    deployed = cache :__deployment__ do
        run :__deployment__, nodes
    end

    exp_result = run :__experiment__, deployed
    run :__collection__
    run :__analysis__, exp_result

end

# helpers

def nodes(&block)
    return $engine.process(:__reservation__, NODES_OPTS, &block)
end

def deployment(name = nil, &block)
    if name.nil?
        return $engine.process(:__deployment__, DEPLOYMENT_OPTS, &block)
    else
        return $engine.process(:__deployment__, DEPLOYMENT_OPTS) { |nodes| run(name, nodes) }
    end
end

def body(&block)
    return $engine.process(:__experiment__, EXPERIMENT_OPTS,  &block)
end

def analysis(&block)
    return $engine.process(:__analysis__, ANALYSIS_OPTS, &block)
end


# importer of subexperiments
# TODO: this is rather ugly!

def with_sublibrary()
    exp = nil
    begin
        old_engine = $engine
        exp = $engine = XPFlow::BasicLibrary.new
        yield
    ensure
        $engine = old_engine
    end
    return exp
end

def import(name, path = nil, opts = {})
    if path.nil?
        return import_file(name)
    end
    lib = with_sublibrary do
        Kernel.load(__FILE__, true)
        Kernel.load(path)
    end
    $engine.import_library(name, lib)
    return lib
end

def library(name, &block)
    lib = with_sublibrary do
        Kernel.load(__FILE__, true)
        block.call
    end
    $engine.import_library(name, lib)
    return lib
end

# includes the file as-it-is
def import_file(path)
    return Kernel.load(path)
end

def experiment_entry(&block)
    return $engine.process(:__standard__, &block)
end
