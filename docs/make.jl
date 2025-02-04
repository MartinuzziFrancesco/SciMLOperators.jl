using Documenter, SciMLOperators

include("pages.jl")

makedocs(
    sitename="SciMLOperators.jl",
    authors="Chris Rackauckas, Alex Jones",
    modules=[SciMLOperators],
    clean=true,doctest=false,
    format = Documenter.HTML(analytics = "UA-90474609-3",
                             assets = ["assets/favicon.ico"],
                             canonical="https://scimlbase.sciml.ai/stable/"),
    pages=pages
)

deploydocs(
   repo = "github.com/SciML/SciMLOperators.jl.git";
   push_preview = true
)
