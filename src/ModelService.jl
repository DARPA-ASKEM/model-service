module ModelService

# See Genie framework example here
# https://genieframework.github.io/Genie.jl/dev/tutorials/5--Handling_Query_Params.html
#
# See also this notebook
# https://github.com/AlgebraicJulia/Structured-Epidemic-Modeling/

using UUIDs
using Genie
using Genie.Requests
using Genie.Renderer.Json
using JSON: json, parse

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.Programs
using Catlab.WiringDiagrams
using Catlab.Graphics.Graphviz
using AlgebraicPetri
using OrdinaryDiffEq
using EasyModelAnalysis
using Latexify
include("./model-transform/stratification.jl")


const modelDict = Dict{String, LabelledPetriNet}()

# heatlhcheck
route("/") do
	return json("model-service running")
end

# convert petri to latex
#
# This expects a json body of a petri ascet:
#
# {
#   S: [ ...]
#   T: [ ...]
#   I: [ ...]
#   O: [ ...]
# }
#
route("/api/petri-to-latex", method = POST) do
    payload = jsonpayload()
    model = parse_json_acset(LabelledPetriNet, json(payload))
		model_odesys = ODESystem(model)
		model_latex = latexify(model_odesys)
		println(model_latex.s)

		return model_latex.s
end

# Retrieve a model
route("/api/models/:model_id") do
    key = payload(:model_id)
    println(" Checking key $(key) => $(haskey(modelDict, key))")

    if !haskey(modelDict, key)
        return json("not found")
    end
    model = modelDict[key]
    return json(model)
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

    return json(
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
        return json("not found")
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

    return json("done")
end


# Get JSON representation of the model
route("/api/models/:model_id/json") do
    key = payload(:model_id)

    if !haskey(modelDict, key)
        return json("not found")
    end

    model = modelDict[key]
    dataOut = generate_json_acset(model)

    return json(dataOut)
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

    return json(
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
    model = parse_json_acset(LabelledPetriNet, json(payload["model"]))
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
    return json(dataOut)
end


################################################################################
# Remove subgraph to a model
# TODO
################################################################################
route("/api/rem-parts", method = POST) do
    return json(
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
    model = parse_json_acset(LabelledPetriNet, json(payload["model"]))

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

    return json(
         Dict([
               (:t, solution.t),
               (:u, solution.u),
               (:variables, variableNames)
         ])
    )
end

################################################################################
# Combine petrinets
#
# Input:
# {
#   modelA: a JSON-serialized petri net
#   modelB: a JSON-serialized petri net
#   statesToMerge: a list of pairs of states (one from each model) that should be combined as part of this operation.
# }
################################################################################
route("/api/models/model-composition", method = POST) do
    data = parse(rawpayload()) # Converts JSON to dictionary thoroughly

    # Check for invalid input
    if !haskey(data, "modelA") || !haskey(data, "modelB") || !haskey(data, "statesToMerge")
        return json("Invalid input")
    end

    if length(data["statesToMerge"]) < 1
        return json("Empty statesToMerge array")
    end

    modelA::Dict{String, Array{Dict{String, Any}, 1}} = data["modelA"]
    modelB::Dict{String, Array{Dict{String, Any}, 1}} = data["modelB"]
    statesToMerge::Array{Dict{String,String},1} = data["statesToMerge"]

    # Find ID of the states to merge based on order of names
    IDsToMerge = Dict{String, Array{Int64}}("modelA" => [], "modelB" => [])

    # Find IDs to merge and check if modelA/B and statesToMerge have their required attributes
    for modelName in ["modelA", "modelB"]
        if !haskey(data[modelName], "S") || !haskey(data[modelName], "T") || !haskey(data[modelName], "I") || !haskey(data[modelName], "O")
            return json("$modelName is missing S, T, I, O attribute")  # Only level checked for model keys, sname/tname/os etc. are not checked yet
        end
        # Loop through states to merge
        for i in 1:length(statesToMerge)
            if !haskey(statesToMerge[i], modelName)
                return json("statesToMerge array is missing model name: $modelName")
            end
            stateIsFound = false
            stateNameToMerge = statesToMerge[i][modelName]
            # Loop through model state names
            for j in 1:length(data[modelName]["S"])
                modelStateName = data[modelName]["S"][j]["sname"]
                # Save ID of model state name which is going to be merged
                if stateNameToMerge == modelStateName
                    if j in IDsToMerge[modelName]
                        return json("The same ID can't be merged twice.")
                    end
                    stateIsFound = true
                    push!(IDsToMerge[modelName], j)
                    break
                end
            end
            if !stateIsFound
                return json("statesToMerge label '$stateNameToMerge' is not found in $modelName")
            end
        end
    end

    mergedModel = deepcopy(modelA) # Will represent the merged petrinet (make a copy of modelA and add on to it)

    # Merge names of places that will be merged
    for i in 1:length(statesToMerge)
        nameToMergeA = mergedModel["S"][IDsToMerge["modelA"][i]]["sname"]
        nameToMergeB = modelB["S"][IDsToMerge["modelB"][i]]["sname"]

        # Merge names, plan to remove name from modelB
        mergedModel["S"][IDsToMerge["modelA"][i]]["sname"] = string(nameToMergeA, nameToMergeB)
        modelB["S"][IDsToMerge["modelB"][i]]["sname"] = nothing # Replace index which holds sname with nothing
    end
    deleteat!(modelB["S"], findall(i -> i == Dict("sname" => nothing), modelB["S"])) # Remove names that were merged from modelB

    append!(mergedModel["S"], modelB["S"]) # Append the rest of the modelB state names that don't merge with modelA states
    append!(mergedModel["T"], modelB["T"]) # Append modelB transitions to modelA

    #= Merge inputs and outputs =#
    lastGreatestID = length(modelA["S"]) + 1
    updatedIDs = [] # Remember IDs that were updated
    amountToIncrease = [] # If we come across the same ID this will tell us how much it should be increased by

    # Update IDs in model B so the places that are not merged in modelA and B are recognized as unique
    for io in [("I", "is", "it"), ("O", "os", "ot")]
        IO = io[1]
        stateID = io[2]
        transitionID = io[3]

        for IDs in modelB[IO] # IDs = {os: stateID, ot: transitionID} or {is: stateID, it: transitionID}
            # If the place is supposed to merge make the ID of the place from modelB the same as the one from modelA
            if IDs[stateID] in IDsToMerge["modelB"]
                index = findfirst(id -> id == IDs[stateID], IDsToMerge["modelB"])
                IDs[stateID] = IDsToMerge["modelA"][index]
            # If we are coming across the same ID again we should increase it by the same amount we did before
            elseif IDs[stateID] in updatedIDs
                index = findfirst(id -> id == IDs[stateID], updatedIDs)
                IDs[stateID] = amountToIncrease[index]
            # This is a new ID so we assign it with an ID higher than the greatest ID
            else
                push!(updatedIDs, IDs[stateID])
                push!(amountToIncrease, lastGreatestID)
                IDs[stateID] = lastGreatestID
                lastGreatestID += 1
            end
            IDs[transitionID] += length(modelA["T"]) # Last transition ID of modelA
        end
        append!(mergedModel[IO], modelB[IO]) # Append modelB inputs/outputs to modelA
    end

    return json(mergedModel)
end

function start()
		# Configuration
		# FIXME: Remove this later when quarkus API sever is fully configured to do forwarding/proxying routes
		Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
		Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
		Genie.config.cors_headers["Access-Control-Allow-Methods"] ="GET,POST,PUT,DELETE,OPTIONS"
		Genie.config.cors_allowed_origins = ["*"]

		Genie.Configuration.config!(
			 cors_allowed_origins = ["*"]
		)

		# Start the API
		up(8888, "0.0.0.0", async = false)
end


end # module
