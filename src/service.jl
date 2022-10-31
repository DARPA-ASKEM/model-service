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
using OrdinaryDiffEq


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

#Currently just uses 2 hardcoded labelled petri nets and stratifies them
#Will need to add many options
#1) Model A -> LabelledPetriNet
#2) Model B -> LabelledPetriNet
#3) TypeP -> LabelledPetriNet
route("/api/models/stratify/:modelAID/:modelBID/:typeModelID") do
    keyA = payload(:modelAID)
    if !haskey(modelDict, keyA)
        return json("not found")
    end
    keyB = payload(:modelBID)
    if !haskey(modelDict, keyB)
        return json("not found")
    end
    keyType = payload(:typeModelID)
    if !haskey(modelDict, keyType)
        return json("not found")
    end

    modelA = modelDict[keyA]
    modelB = modelDict[keyB]
    typesP = modelDict[keyType]

    #remove the names for types
    types = map(typesP, Name=name->nothing) 
    
    #=
    https://github.com/AlgebraicJulia/Catlab.jl/blob/master/src/categorical_algebra/CSets.jl 
    Warning this is said to work in exponential time (NP Problem)
    Parameters:
        1) LabelledPetriNet
        2) LabelledPetriNet (type)
        3) ?
        4) ?
    output:
        ACSetTransformation object
    =#
    modelATyped = homomorphism(modelA, types;
        initial=(T=[1,2,2],I=[1,2,3,3],O=[1,2,3,3]),
        type_components=(Name=x->nothing,)
    )

    modelBTyped = homomorphism(modelB, types;
        initial=(T=[3,3],), type_components=(Name=x->nothing,)
    )

    res = stratify(modelATyped=>[[:strata],[:strata],[:strata],[]], # S I R D
        modelBTyped=>[[:disease], [:disease,:infect]],# Q NQ 
        typesP
    ) 

    # println("Model A")
    # println(generate_json_acset(modelA))

    # println("Model B")
    # println(generate_json_acset(modelB))
    
    # println("Type Model")
    # println(generate_json_acset(typesP))

    println("Result:")
    println(res)
    dataOut = generate_json_acset(res)
    return json(dataOut)

    
end


"""
I am quite surprised we need to add the following two functions. Seems like they should be in CatLab to me
Modify a typed petri net to add cross terms
"""
function add_cross_terms(pn_crossterms, type_system)
  typed_pn, crossterms = deepcopy.(pn_crossterms)
  pn = dom(typed_pn)
  type_comps = Dict([k=>collect(v) for (k,v) in pairs(components(typed_pn))])
  for (s_i,cts) in enumerate(crossterms)
    for ct in cts 
      type_ind = findfirst(==(ct), type_system[:tname])
      is, os = [incident(type_system, type_ind, f) for f in [:it, :ot]]
      new_t = add_part!(pn, :T; tname=ct)
      add_parts!(pn, :I, length(is); is=s_i, it=new_t)
      add_parts!(pn, :O, length(os); os=s_i, ot=new_t)
      push!(type_comps[:T], type_ind)
      append!(type_comps[:I], is); append!(type_comps[:O], os); 
    end
  end
  return homomorphism(pn, codom(typed_pn); initial=type_comps, 
                      type_components=(Name=x->nothing,),)
end

"""Add cross terms before taking pullback"""
function stratify(pn1, pn2, type_system)
  return pullback([add_cross_terms(pn, type_system) for pn in [pn1, pn2]]) |> apex
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
