FROM gitpod/workspace-full

# Install custom tools, runtime, etc.
RUN brew install dub && brew install dmd