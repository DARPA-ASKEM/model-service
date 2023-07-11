module ModelService

using UUIDs
using Genie
using Genie.Requests
using Genie.Renderer.Json
using JSON: json, parse

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.Programs
using Catlab.WiringDiagrams
using AlgebraicPetri
using ModelingToolkit
using Latexify

import YAML: load
using SwagUI
import SwaggerMarkdown: build, @swagger, OpenAPI, DOCS


include("./ASKEMPetriNets.jl")
using .ASKEMPetriNets

export start!

# heatlhcheck
@swagger """
/:
 get:
  summary: Healthcheck
  description: A basic healthcheck for the model service
  responses:
     '200':
         description: Returns notice that service has started
"""
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

@swagger """
/api/petri-to-latex:
 post:
  summary: ACSet to LaTex
  description: Convert an ACSet into a LaTeX string by ways of ODESystem
  requestBody:
     description: Arguments to pass into conversion
     required: true
     content:
         application/json:
             schema:
                 type: object
                 properties:
                     S:
                         type: array
                     T:
                         type: array
                     I:
                         type: array
                     O:
                         type: array
  responses:
     '200':
         description: Returns LaTex string
"""
route("/api/petri-to-latex", method = POST) do
    payload = jsonpayload()
    model = parse_json_acset(LabelledPetriNet, json(payload))
		model_odesys = ODESystem(model)
		model_latex = latexify(model_odesys)
		println(model_latex.s)

		return model_latex.s
end


@swagger """
/api/stratify:
 post:
  summary: Stratify
  description: Given two typed AMR Petrinets, perform stratification and return result as AMR Petrinet
  requestBody:
     description: Arguments to pass into conversion
     required: true
     content:
         application/json:
             schema:
                 type: object
                 properties:
                     baseMOdel:
                         type: object
                     fluxModel:
                         type: object
  responses:
     '200':
         description: Returns new model

"""
route("/api/stratify", method=POST) do
  # payload = jsonpayload()
	rawPayload = rawpayload()
	jsonData = parse(rawPayload)

	baseModel = jsonData["baseModel"]
	fluxModel = jsonData["fluxModel"]

	x = TypedASKEMPetriNet(ASKEMPetriNet(baseModel))
	y = TypedASKEMPetriNet(ASKEMPetriNet(fluxModel))

	result = StratifiedASKEMPetriNet(x, y)

	return json(result)
end

# Generate swagger-ui docs
info = Dict("title" => "Model Service", "version" => "0.1.0")
openAPI = OpenAPI("3.0.0", info)
openAPI.paths = load(join(DOCS)) # NOTE: Has to be done manually because it's broken in SwaggerMarkdown
documentation = build(openAPI)

route("/docs") do
    render_swagger(documentation)
end

function start!()
	  println("Starting model service")
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
		println("Model service started!!")
end


end # module
