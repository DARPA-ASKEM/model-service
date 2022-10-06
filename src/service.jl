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

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.Programs
using Catlab.WiringDiagrams
using Catlab.Graphics.Graphviz
using AlgebraicPetri

const modelDict = Dict{String, LabelledPetriNet}()


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
        subparts = model.subparts

        for e in data["edges"]

            source = Symbol(e["source"])
            target = Symbol(e["target"])

            if isnothing(findfirst(x -> x == source, subparts.sname)) == false
                sourceIdx = findfirst(x -> x == source, subparts.sname)
                targetIdx = findfirst(x -> x == target, subparts.tname)

                add_parts!(model, :I, 1, is=sourceIdx, it=targetIdx)
            end

            if isnothing(findfirst(x -> x == source, subparts.tname)) == false
                sourceIdx = findfirst(x -> x == source, subparts.tname)
                targetIdx = findfirst(x -> x == target, subparts.sname)

                add_parts!(model, :O, 1, os=sourceIdx, ot=targetIdx)
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
