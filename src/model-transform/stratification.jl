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

function stratificationEndPoint(modelAID, modelBID, typeModelID)
    keyA = payload(modelAID)
    keyB = payload(modelBID)
    keyType = payload(typeModelID)
    if !haskey(modelDict, keyA) || !haskey(modelDict, keyB) || !haskey(modelDict, keyType)
        return json("one or more models not found")
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

    println("Result:")
    println(res)
    stratifiedModel = generate_json_acset(res)
    return json(stratifiedModel)
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