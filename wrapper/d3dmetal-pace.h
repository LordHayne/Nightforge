// Nightforge's frame limit for games on Apple's D3DMetal (d3dmetal-pace.m, part of hide-steam-dock.dylib).
#ifndef NIGHTFORGE_D3DMETAL_PACE_H
#define NIGHTFORGE_D3DMETAL_PACE_H

#include <stddef.h>

// The limit a process gets, 0 for none. Three things have to agree, each from a different place:
// `limit` – D3DM_MAX_FPS from the environment the process inherited (1…1000);
// `permit` – the text of Nightforge's permit file, written for one start only and never for a game with an
//   anti-cheat or a cheat protection of its own: "<limit>\n<Windows folder of the game>\n";
// `program` – the process's argv[0], which Wine sets to the Windows path of the program it runs.
// The program has to lie in the permit's folder (case and slashes aside), and the permit has to name the same limit.
int nightforge_pace_limit(const char *limit, const char *permit, const char *program);

// Whether `image` (a path dyld loads) is Apple's D3DMetal.framework.
int nightforge_is_d3dmetal(const char *image);

#endif
