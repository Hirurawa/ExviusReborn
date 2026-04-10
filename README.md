# Gacha Project

## Project Overview
This repository contains a Godot 4 Gacha game client paired with a Nakama server backend. The primary purpose of this project is to provide a complete, end-to-end architecture for a mobile-style gacha game, separating the "dumb" UI view layer on the client from the authoritative game state and logic handled by the server. This document serves as the "Billboard" for AI agents and developers to understand the broad strokes of the project structure and how to run it.

## Directory Map
* `/godot` - Contains the Godot 4 project, including all client-side logic, UI components, scenes, and assets.
* `/nakama` - Contains the Nakama server backend setup, including the Docker configuration and the authoritative Lua modules that manage game state, player data, and server RPCs.

## Getting Started (Server)
The backend requires Docker and Docker Compose. To spin up the Nakama server, database, and asset server:
1. Navigate to the `nakama` directory.
2. Run the following command:
   ```bash
   docker-compose up -d
   ```
3. The Nakama server will be accessible, and the database will be initialized automatically.

## Getting Started (Client)
1. Open the Godot 4 engine.
2. Import the project by selecting the `godot/project.godot` file.
3. The main entry point for the game client is the scene located at `godot/demo.tscn`. You can run this scene directly to start the client application.
