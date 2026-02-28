# Agent Core Runtime IaC

## Setup (uv + virtual environment)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv venv
source .venv/bin/activate   # Linux/macOS
# .venv\Scripts\activate   # Windows
source .venv/Scripts/activate  # Git bash
uv pip sync pyproject.toml
UV_PROJECT_ENVIRONMENT=.venv
uv add zmq
python -m ipykernel install --user --name=.venv --display-name="Python (uv env)"
```
