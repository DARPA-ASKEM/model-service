FROM julia:1.8.1

COPY src /model-service

# Pre-install Catlab related dependencies
RUN julia -e 'import Pkg; Pkg.update()' && \
    julia -e 'import Pkg; Pkg.add("UUIDs"); using UUIDs' && \
    julia -e 'import Pkg; Pkg.add(Pkg.PackageSpec(; name="Catlab", version="0.14.8")); using Catlab' && \
    julia -e 'import Pkg; Pkg.add(Pkg.PackageSpec(; name="AlgebraicPetri", version="0.7.3")); using AlgebraicPetri' && \
    julia -e 'import Pkg; Pkg.add(Pkg.PackageSpec(; name="DifferentialEquations", version="7.5.0")); using DifferentialEquations' && \
    julia -e 'import Pkg; Pkg.add(Pkg.PackageSpec(; name="OrdinaryDiffEq", version="6.29.2")); using OrdinaryDiffEq' && \
    julia -e 'import Pkg; Pkg.add("Genie"); using Genie' && \
    julia -e 'import Pkg; Pkg.add("JSON"); using JSON'

CMD ["julia", "model-service/service.jl"]
