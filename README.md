# Model Transform
This is a webservice that provies a REST-API wrappers around [Catlab.jl](https://github.com/AlgebraicJulia/Catlab.jl). 


## Docker image
The Dockerfile provides a runnable web-service

```
docker build . -t askem-model-transform
```

> relies on [data-store-api/fg/dev-cleanup](https://github.com/DARPA-ASKEM/data-store-api/tree/fg/dev-cleanup)