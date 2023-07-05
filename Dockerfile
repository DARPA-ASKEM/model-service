# See https://github.com/GenieFramework/Genie.jl/issues/174
FROM julia:1.9

WORKDIR /model-service

# Install requirements
COPY Manifest.toml  /model-service/
COPY Project.toml /model-service/

# Install local package
COPY src/ /model-service/src/
RUN julia -e 'using Pkg; Pkg.activate("."); Pkg.instantiate(); Pkg.precompile();'

# CMD [ "julia", "-e", "using Pkg; Pkg.activate(\".\"); include(\"/model-service/src/service.jl\"); ModelService.start()" ]
CMD [ "julia", "-e", "using Pkg; Pkg.activate(\".\"); include(\"/model-service/src/ModelService.jl\"); ModelService.start!()" ]

