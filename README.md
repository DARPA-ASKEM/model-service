# Model Service
This is a webservice that provies a REST-API wrappers around Julia and [Catlab.jl](https://github.com/AlgebraicJulia/Catlab.jl). 

## Docker image
The Dockerfile provides a runnable web-service

```
$ docker build . -t askem-model-service
$ docker run -p 8888:8888 askem-model-service
```
