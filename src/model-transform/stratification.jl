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

    res = appendIndexes(res)
    stratifiedModel = generate_json_acset(res)
    return json(stratifiedModel)
end

"""
I am quite surprised we need to add the following two functions. Seems like they should be in CatLab to me
Modify a typed petri net to add cross terms
"""
#Parameters:
#   petri_net_crossterms: a typed petrinet (ACSetTransformation) with a provided vector.
#   Add new transitions and edges to petri net
#Result:
#   The output of adding the new transitions to the provided petri net along with their edges.
function add_cross_terms(petri_net_crossterms, type_system)
  typed_petri_net, crossterms = deepcopy.(petri_net_crossterms) #separate the provided petri net with the provided vector crossterms
  petri_net = dom(typed_petri_net) #Take LabelledPetriNet from provided Typed PetriNet
  type_comps = Dict([k=>collect(v) for (k,v) in pairs(components(typed_petri_net))])
  for (state_index,cross_terms) in enumerate(crossterms)
    for ct in cross_terms 
      type_ind = findfirst(==(ct), type_system[:tname])
      is, os = [incident(type_system, type_ind, f) for f in [:it, :ot]]
      new_t = add_part!(petri_net, :T; tname=ct)
      add_parts!(petri_net, :I, length(is); is=state_index, it=new_t)
      add_parts!(petri_net, :O, length(os); os=state_index, ot=new_t)
      push!(type_comps[:T], type_ind)
      append!(type_comps[:I], is); append!(type_comps[:O], os); 
    end
  end
  return homomorphism(petri_net, codom(typed_petri_net); initial=type_comps, 
                      type_components=(Name=x->nothing,),)
end

"""Add cross terms before taking pullback"""
function stratify(petri_net1, petri_net2, type_system)
  return pullback([add_cross_terms(petri_net, type_system) for petri_net in [petri_net1, petri_net2]]) |> apex
end

#We are using labels as though they are IDs at the moment.
#This is causing issues when the labels are identical such as after a stratification
#We will append the indexes to tname to prevent this issue
function appendIndexes(labeledPetri)
    for  i in range(1,length(labeledPetri[:tname]))
        outputName::String = ""
        for ele in labeledPetri[:tname][i]
            outputName = outputName * String(ele) * "_"
        end
        outputName = outputName * string(i)
        #TODO: Fix this to change labeledPetri[:tname][i]'s type.
        #It is stored as a list of tuple(symbol,symbol) after stratification but just a list of symbol before.
        labeledPetri[:tname][i] = tuple(Symbol(outputName),Symbol(""))
    end
    return labeledPetri
end