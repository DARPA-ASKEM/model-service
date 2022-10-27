module demo

# See Genie framework example here
# https://genieframework.github.io/Genie.jl/dev/tutorials/5--Handling_Query_Params.html
#
# See also this notebook
# https://github.com/AlgebraicJulia/Structured-Epidemic-Modeling/

import HTTP
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
using OrdinaryDiffEq


# Retrieve a model
route("/api/models/:model_id") do
    key = payload(:model_id)
    response = HTTP.request(
      "GET", 
      "http://localhost:8000/models/$model_id",
      Dict("Content-type" => "application/json", "Accept" => "text/plain")
    )

    if response.status != 200 
        return json("not found")
    end
    return json(generate_json_acset(response.body["body"]))
end


# Create a new empty model
route("/api/models", method = PUT) do
    randomModelName = string(UUIDs.uuid4())
    printlin("Creating $randomModelName")
 

    # Debugging
    # modelId = "xyz"

    model = LabelledPetriNet()

    response = HTTP.request(
      "POST", 
      "http://localhost:8000/models",
      Dict(
        "Content-type" => "application/json",
        "Accept" => "text/plain"
       ),
      Dict(
        "name" => randomModelName,
        "description" => "none",
        "body" => Dict(
            "operation_type" => "init",
            "model_content" => json(model_content)
        )
      )
    )

    return json(
         Dict([
               (:id, response.body)
         ])
    )
end


# Add nodes and edges, a more natural way of adding components instead of solely relying
# on indices
route("/api/models/:model_id", method = POST) do
    key = payload(:model_id)

    response = HTTP.request(
      "GET", 
      "http://localhost:8000/models/$model_id",
      Dict("Content-type" => "application/json", "Accept" => "text/plain")
    )

    if response.status != 200 
        return json("not found")
    end
    
    model = read_json_acset(json(response.body["body"]))

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
    response = HTTP.request(
      "POST", 
      "http://localhost:8000/models/$key",
      Dict(
        "Content-type" => "application/json",
        "Accept" => "text/plain"
       ),
      Dict(
            "operation_type" => "edit",
            "model_content" => json(generate_json_acset(model_content))
        )
    )

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

    response = HTTP.request(
      "GET", 
      "http://localhost:8000/models/$model_id",
      Dict("Content-type" => "application/json", "Accept" => "text/plain")
    )

    if response.status != 200 
        return json("not found")
    end
    model = json(generate_json_acset(response.body["body"]))

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
