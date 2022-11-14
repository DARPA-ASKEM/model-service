module demo

# See Genie framework example here
# https://genieframework.github.io/Genie.jl/dev/tutorials/5--Handling_Query_Params.html
#
# See also this notebook
# https://github.com/AlgebraicJulia/Structured-Epidemic-Modeling/

using UUIDs
using Genie
using Genie.Requests
using Genie.Renderer.Json
using JSON 

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.Programs
using Catlab.WiringDiagrams
using Catlab.Graphics.Graphviz
using AlgebraicPetri
using OrdinaryDiffEq
include("./model-transform/stratification.jl")
include("./model-transform/renameNodes.jl")


const modelDict = Dict{String, LabelledPetriNet}()


# Retrieve a model
route("/api/models/:model_id") do
    key = payload(:model_id)
    println(" Checking key $(key) => $(haskey(modelDict, key))")

    if !haskey(modelDict, key)
        return JSON.json("not found")
    end
    model = modelDict[key]
    return JSON.json(model)
end


# Create a new empty model
route("/api/models", method = PUT) do
    # @info "Creating new model"
    modelId = string(UUIDs.uuid4())

    # Debugging
    # modelId = "xyz"

    model = LabelledPetriNet()
    modelDict[modelId] = model

    println(modelDict)

    return JSON.json(
         Dict([
               (:id, modelId)
         ])
    )
end


# Add nodes and edges, a more natural way of adding components instead of solely relying
# on indices
route("/api/models/:model_id", method = POST) do
    key = payload(:model_id)
    println(" Checking key $(key) => $(haskey(modelDict, key))")

    if !haskey(modelDict, key)
        return JSON.json("not found")
    end

    model = modelDict[key]
    data = jsonpayload()

    # nodes, need to be processed first, otherwise index assignment will fail for edges
    if haskey(data, "nodes")
        for n in data["nodes"]
            if n["type"] == "S"
                add_parts!(model, :S, 1, sname=Symbol(n["name"]))
            elseif n["type"] == "T"
                add_parts!(model, :T, 1, tname=Symbol(n["name"]))
            end
        end
    end

    # edges
    if haskey(data, "edges")
        # Grab a json/dict object that is easier to inspect and likely less prone
        # to changes
        subpartsDict = generate_json_acset(model)

        for e in data["edges"]

            source = Symbol(e["source"])
            target = Symbol(e["target"])

            if isnothing(findfirst(x -> x.sname == source, subpartsDict[:S])) == false
                sourceIdx = findfirst(x -> x.sname == source, subpartsDict[:S])
                targetIdx = findfirst(x -> x.tname == target, subpartsDict[:T])

                add_parts!(model, :I, 1, is=sourceIdx, it=targetIdx)
            end

            if isnothing(findfirst(x -> x.tname == source, subpartsDict[:T])) == false
                sourceIdx = findfirst(x -> x.tname == source, subpartsDict[:T])
                targetIdx = findfirst(x -> x.sname == target, subpartsDict[:S])

                add_parts!(model, :O, 1, ot=sourceIdx, os=targetIdx)
            end
        end
    end

    # Serialize back
    # println("Serializing back")
    modelDict[key] = model

    return JSON.json("done")
end

#Rename model nodes + transitions based off a model ID
route("/api/models/rename/:model_id", method = POST) do
    data = jsonpayload()
    return(renameNodeEndPoint(:model_id,data))
end

# Get JSON representation of the model
route("/api/models/:model_id/json") do
    key = payload(:model_id)

    if !haskey(modelDict, key)
        return JSON.json("not found")
    end

    model = modelDict[key]
    dataOut = generate_json_acset(model)

    return JSON.json(dataOut)
end



# Run an ODE solver, just testing.
#
# {
#   variables: {
#     <name>: val
#   },
#   parameters: {
#     <name>: val 
#   }
# }
route("/api/models/:model_id/simulate", method = POST) do
    key = payload(:model_id)
    data = jsonpayload()

    if !haskey(modelDict, key)
        return json("not found")
    end
    model = modelDict[key]

    variableNames = []
    variables = Float32[]
    parameters = Float32[]

    subpartsDict = generate_json_acset(model)

    for name in subpartsDict[:S]
        push!(variableNames, name.sname)
        push!(variables, data["variables"][name.sname])
    end

    for name in subpartsDict[:T]
        push!(parameters, data["parameters"][name.tname])
    end

    temp = PetriNet(model)

    problem = ODEProblem(vectorfield(temp), variables, (0.0, 100.0), parameters);
    solution = solve(problem, Tsit5(), abstol=1e-8);

    return JSON.json(
         Dict([
               (:t, solution.t),
               (:u, solution.u),
               (:variables, variableNames)
         ])
    )
end

#Provided the ID of 2 models + the ID of the type model for this
# Stratify said models and return json output
#1) Model A -> LabelledPetriNet
#2) Model B -> LabelledPetriNet
#3) TypeP -> LabelledPetriNet
#TODO: Chat with TA2 to understand better. Especially on the vectors provided to function as theyre hard coded 
#eg) "initial=(T=[1,2,2],I=[1,2,3,3],O=[1,2,3,3])" "[:strata],[:strata],[:strata],[]"
route("/api/models/stratify/:modelAID/:modelBID/:typeModelID") do
    stratifiedModel = stratificationEndPoint(:modelAID,:modelBID,:typeModelID)
    return stratifiedModel
end






################################################################################
# Add subgraph to a model
################################################################################
route("/api/add-parts", method = POST) do
    payload = jsonpayload()
    model = parse_json_acset(LabelledPetriNet, JSON.json(payload["model"]))
    parts = payload["parts"]

    # Add nodes, need to be processed first, otherwise index assignment will fail for edges
    if haskey(parts, "nodes")
        for n in parts["nodes"]
            if n["type"] == "S"
                add_parts!(model, :S, 1, sname=Symbol(n["name"]))
            elseif n["type"] == "T"
                add_parts!(model, :T, 1, tname=Symbol(n["name"]))
            end
        end
    end

    # Add edges
    if haskey(parts, "edges")
        # Grab a json/dict object that is easier to inspect and likely less prone to changes
        subpartsDict = generate_json_acset(model)

        for e in parts["edges"]

            source = Symbol(e["source"])
            target = Symbol(e["target"])

            if isnothing(findfirst(x -> x.sname == source, subpartsDict[:S])) == false
                sourceIdx = findfirst(x -> x.sname == source, subpartsDict[:S])
                targetIdx = findfirst(x -> x.tname == target, subpartsDict[:T])

                add_parts!(model, :I, 1, is=sourceIdx, it=targetIdx)
            end

            if isnothing(findfirst(x -> x.tname == source, subpartsDict[:T])) == false
                sourceIdx = findfirst(x -> x.tname == source, subpartsDict[:T])
                targetIdx = findfirst(x -> x.sname == target, subpartsDict[:S])

                add_parts!(model, :O, 1, ot=sourceIdx, os=targetIdx)
            end
        end
    end

    dataOut = generate_json_acset(model)
    return JSON.json(dataOut)
end


################################################################################
# Remove subgraph to a model
# TODO
################################################################################
route("/api/rem-parts", method = POST) do
    return JSON.json(
         Dict([
               (:msg, "Not implemented")
         ])
    )
end


################################################################################
# Simulate a petrinet model
# This is a placeholder for testing ideas for the HMI to deal with parameterization and to deal
# with simulation output. This will be deprecated once query/simulation plans come online.
#
# Input:
# {
#   model: { ... },
#   variables: { [variable1]: val, [variable2]: val, ... }
#   parameters: { [param1]: val, [param2]: val, ... }
# }
################################################################################
route("/api/simulate", method = POST) do
    payload = jsonpayload()
    model = parse_json_acset(LabelledPetriNet, JSON.json(payload["model"]))

    variableNames = []
    variables = Float32[]
    parameters = Float32[]

    subpartsDict = generate_json_acset(model)

    for name in subpartsDict[:S]
        push!(variableNames, name.sname)
        push!(variables, payload["variables"][name.sname])
    end

    for name in subpartsDict[:T]
        push!(parameters, payload["parameters"][name.tname])
    end

    temp = PetriNet(model)
    problem = ODEProblem(vectorfield(temp), variables, (0.0, 100.0), parameters);
    solution = solve(problem, Tsit5(), abstol=1e-8);

    return Json.json(
         Dict([
               (:t, solution.t),
               (:u, solution.u),
               (:variables, variableNames)
         ])
    )
end


# Configuration
# FIXME: Remove this later when quarkus API sever is fully configured to do forwarding/proxying routes
Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
Genie.config.cors_headers["Access-Control-Allow-Methods"] ="GET,POST,PUT,DELETE,OPTIONS"
Genie.config.cors_allowed_origins = ["*"]

# Genie.Configuration.config!(
#    cors_allowed_origins = ["*"]
# )


# Start the API
up(8888, "0.0.0.0", async = false)

end # module
