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

function renameNodeEndPoint(modelID, data)
    key = payload(modelID)
    println(" Checking key $(key) => $(haskey(modelDict, key))")

    if !haskey(modelDict, key)
        return JSON.json("not found")
    end

    model = modelDict[key]
    #data = jsonpayload()
    println("Data: ")
    println(data)
    # nodes, need to be processed first, otherwise index assignment will fail for edges
    if haskey(data, "transitions")
        println("=== transitions: ===")
        println(typeof(data["transitions"]))
        println(data["transitions"])
        println("----")
        println(data["transitions"][1]["tname"])
        println("*****")
        println(model[:tname])
        for i in range(1,length(data["transitions"]))
            model[:tname][i] = Symbol(data["transitions"][i]["tname"])
        end
        println("End Result:")
        println(model)
    end
    if haskey(data, "states")
        for i in range(1,length(data["states"]))
            model[:sname][i] = Symbol(data["states"][i]["sname"])
        end
    end
    
    modelDict[key] = model
    return JSON.json("Done")
end
