WebGL Forward+ and Clustered Deferred Shading
======================

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 4**

* Christina Qiu
  * [LinkedIn](https://www.linkedin.com/in/christina-qiu-6094301b6/), [personal website](https://christinaqiu3.github.io/), [twitter](), etc.
* Tested on: Windows 11, Intel Core i7-13700H @ 2.40GHz, 16GB RAM, NVIDIA GeForce RTX 4060 Laptop GPU (Personal laptop)

### Live Demo

[![](<Screenshot 2025-10-18 234605.png>)](http://christinaqiu3.com/Project4-WebGPU-Forward-Plus-and-Clustered-Deferred)

### Demo Video/GIF

[![](hw_4_1-1.gif)]

(30+ second video/gif of your project running)

## OVERVIEW

This project implements a small GPU renderer in WebGPU with three progressively more advanced rendering methods and the supporting infrastructure needed to compare them.

### Naive renderer

Implemented a functional rasterization-based naive pipeline as a baseline. Key work: created and uploaded a camera view–projection uniform buffer from camera.ts, added the buffer to a bind group used by the naive pipeline, and updated the vertex shader to transform vertices with the view-proj matrix. This exposes the basic host→GPU data flow (create buffer, write buffer, bind group, pipeline layout, shader use) and provides a reference image and timing for later comparisons.

### Forward+ (clustered forward shading)

Implemented tiled (X × Y × Z) clustering of the camera frustum on the GPU via a compute shader. For each cluster we compute view-space AABB bounds (logarithmic Z slicing), test all scene lights for overlap, and store light indices and counts in a cluster buffer. During fragment shading the shader looks up the fragment’s cluster and only accumulates the lights assigned to that cluster. This greatly reduces per-fragment light loops for scenes with many lights. 

Important implementation notes:

* Camera uniforms include invProj/view matrices and near/far to enable NDC → view unprojection in the compute shader.

* Cluster storage is a tightly packed structured buffer: a light count, fixed-size light index array, and cluster AABB. Host-side allocation mirrors WGSL alignment and padding.

* The clustering compute pass is dispatched once per frame before the G-buffer / shading passes.

### Clustered Deferred (G-buffer + fullscreen lighting)

Reused the Forward+ clustering to build a deferred lighting pipeline: first render geometry into a G-buffer (position, normal, albedo), then run a fullscreen pass that samples the G-buffer and accumulates lights from the fragment’s cluster (using the same cluster buffer). This separates geometry shading from expensive per-light lighting and decouples material evaluation from lighting accumulation.

### Notes

* Memory layout and alignment: when creating structured storage/uniform buffers for WGSL, the host layout must match WGSL’s std140-like packing rules. I checked field offsets and padded host buffers so device.createBindGroup and shader reads align correctly.

* Logarithmic Z slicing: implemented the usual log-based formula for slice boundaries to balance near/far precision and avoid excessive near-plane clustering.

* Light culling: cluster tests use sphere-vs-AABB intersection in view space for a conservative inclusion test.

* Render pass correctness: G-buffer (3 targets) and fullscreen (swapchain) use separate render passes; pipeline fragment target formats must match the render pass attachments exactly.

* Tradeoffs: Forward+/Clustered Deferred pay a setup cost (clustering compute pass and extra buffers) and are most beneficial when scene light counts are large. For scenes with few lights, the clustering overhead can outweigh benefits.

## Performance Analysis

### Forward+ vs. Clustered Deferred Shading



In my implementation, Forward+ shading consistently ran faster than Clustered Deferred for moderate to high light counts. The Clustered Deferred method would be slightly more efficient when the fragment shading workload is heavy (e.g., expensive BRDFs or high material variation), since lighting is decoupled from geometry and done in a fullscreen pass.

Naive shading (for baseline): 14FPS when numlights = 500. 1FPS when numlights = 5000. 

* Slowest under many lights because every fragment loops over all lights globally.

Forward+ average frame time: 60FPS when numlights = 500. 20 FPS when numlights = 5000.

* Performs lighting in a single geometry pass, writing directly to the framebuffer. This avoids the cost of:
  * Creating and writing large G-buffers (position, normal, albedo textures).
  * Performing a second fullscreen pass to read and combine them.

Clustered Deferred average frame time: 11FPS when numlights = 500. 11FPS when numlights = 5000. 

* Due to multiple render passes, and each G-buffer write/read consumes GPU memory bandwidth. 
* Clustered Deferred becomes advantageous when:
  * Materials are complex (many parameters or procedural shading). Deferred shading stores pre-shaded attributes and performs lighting only once in screen space.
  * The number of lights is extremely large


Performance Differences

* Memory Bandwidth: Deferred shading writes multiple 16-bit/32-bit render targets per fragment, which is expensive even if lighting is cheaper. Forward+ skips that entirely.

* Fill Rate: Deferred pipelines are more fill-rate–limited since every pixel is written 3–4 times per G-buffer attachment.

* Depth Culling: Forward+ benefits from early-Z rejection before lighting; deferred pipelines shade all visible pixels regardless.

* Lighting Complexity: Both use the same clustered light indexing, so the per-fragment lighting cost scales equally. The main difference is whether that lighting happens once or after a G-buffer stage.







### Credits

- [Vite](https://vitejs.dev/)
- [loaders.gl](https://loaders.gl/)
- [dat.GUI](https://github.com/dataarts/dat.gui)
- [stats.js](https://github.com/mrdoob/stats.js)
- [wgpu-matrix](https://github.com/greggman/wgpu-matrix)
- [Ortiz Blog](https://www.aortiz.me/2018/12/21/CG.html#forward-shading)




Optimize your TypeScript and/or WGSL code. Chrome's profiling tools are useful for this. For each change that improves performance, show the before and after render times.



For each new effect feature (required or extra), please provide the following analysis:

Concise overview and explanation of the feature.
Performance change due to adding the feature.
If applicable, how do parameters (such as number of lights, number of tiles, etc.) affect performance? Show data with graphs.
Show timing in milliseconds, not FPS.
If you did something to accelerate the feature, what did you do and why?
How might this feature be optimized beyond your current implementation?
For each performance feature (required or extra), please provide:

Concise overview and explanation of the feature.
Detailed performance improvement analysis of adding the feature.
What is the best case scenario for your performance improvement? What is the worst? Explain briefly.
Are there tradeoffs to this performance feature? Explain briefly.
How do parameters (such as number of lights, number of tiles, etc.) affect performance? Show data with graphs.
Show timing in milliseconds, not FPS.
Show debug views when possible.
If the debug view correlates with performance, explain how.