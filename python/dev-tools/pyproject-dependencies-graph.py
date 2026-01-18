# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "tomli",
#   "networkx",
#   "rich",
# ]
# ///

import sys
import tomli
import networkx as nx
from pathlib import Path
from rich.console import Console

console = Console()

def read_dependencies(project_path: Path) -> set[str]:
    """Reads the dependencies from pyproject.toml in the given project directory."""
    pyproject_file = project_path / "pyproject.toml"
    if not pyproject_file.exists():
        return set()

    try:
        with open(pyproject_file, "rb") as f:
            data = tomli.load(f)

        return set(data.get("project", {}).get("dependencies", []))
    except Exception as e:
        console.print(f"[red]Failed to read dependencies from {pyproject_file}: {e}[/red]")
        return set()

def build_dependency_graph(projects: list[Path]) -> nx.DiGraph:
    """Creates a dependency graph of projects."""
    graph = nx.DiGraph()
    
    project_names = {p.name: p for p in projects}  # Map project name to path
    
    for project in projects:
        graph.add_node(project.name)
        dependencies = read_dependencies(project)
        
        for dep in dependencies:
            dep_name = dep.split("==")[0]  # Strip version info if present
            if dep_name in project_names:
                graph.add_edge(dep_name, project.name)  # Add dependency link

    return graph

def get_merge_order(graph: nx.DiGraph) -> list[str]:
    """Returns the projects in the correct merge order."""
    try:
        return list(nx.topological_sort(graph))
    except nx.NetworkXUnfeasible:
        console.print("[red]Cycle detected in dependencies! Manual resolution required.[/red]")
        sys.exit(1)

def main():
    if len(sys.argv) != 2:
        console.print(f"Usage: {sys.argv[0]} <projects_file>")
        sys.exit(1)

    projects_file = Path(sys.argv[1])
    if not projects_file.exists():
        console.print(f"[red]Error: File {projects_file} not found![/red]")
        sys.exit(1)

    with open(projects_file, "r") as f:
        projects = [Path(line.strip()) for line in f if line.strip()]

    graph = build_dependency_graph(projects)
    merge_order = get_merge_order(graph)

    console.print("[green]Recommended merge order:[/green]")
    for i, project in enumerate(merge_order, 1):
        console.print(f"{i}. {project}")

if __name__ == "__main__":
    main()