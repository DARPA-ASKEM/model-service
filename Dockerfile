FROM julia:1.8.1

ADD src /model-transform

# Pre-install Catlab related dependencies
RUN julia -e 'import Pkg; Pkg.update()' && \
    julia -e 'import Pkg; Pkg.add("UUIDs"); using UUIDs' && \
    julia -e 'import Pkg; Pkg.add("Catlab"); using Catlab' && \
    julia -e 'import Pkg; Pkg.add("Genie"); using Genie' && \
    julia -e 'import Pkg; Pkg.add("AlgebraicPetri"); using AlgebraicPetri' && \
    julia -e 'import Pkg; Pkg.add("DifferentialEquations"); using DifferentialEquations' && \
    julia -e 'import Pkg; Pkg.add("OrdinaryDiffEq"); using OrdinaryDiffEq' && \
    julia -e 'import Pkg; Pkg.add("JSON"); using JSON'

CMD julia model-transform/service.jl
