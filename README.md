# Model Service
This is a webservice that provies REST-API wrappers around Julia and [Catlab.jl](https://github.com/AlgebraicJulia/Catlab.jl). 
In the current form (Feb 2023) it provides features to create, manipulat, and transform ODE/Petrinet models.

## Dependencies
Model service is compatible and built with Julia 1.8.x.

## Running locally
From the project directory, start `julia`
```
# Initialize
using Pkg;
Pkg.activate(".");
Pkg.instantiate();

# Run the webserver
include("./src/ModelService.jl")
ModelService.start();
```


## Build docker image
The Dockerfile provides a runnable web-service

```
$ docker build . -t askem-model-service
$ docker run -p 8888:8888 askem-model-service
```
