import { vec3 } from "wgpu-matrix";
import { device } from "../renderer";

import * as shaders from '../shaders/shaders';
import { Camera } from "./camera";

// h in [0, 1]
function hueToRgb(h: number) {
    let f = (n: number, k = (n + h * 6) % 6) => 1 - Math.max(Math.min(k, 4 - k, 1), 0);
    return vec3.lerp(vec3.create(1, 1, 1), vec3.create(f(5), f(3), f(1)), 0.8);
}

export class Lights {
    private camera: Camera;

    numLights = 500;
    static readonly maxNumLights = 5000;
    static readonly numFloatsPerLight = 8; // vec3f is aligned at 16 byte boundaries

    static readonly lightIntensity = 0.1;

    lightsArray = new Float32Array(Lights.maxNumLights * Lights.numFloatsPerLight);
    lightSetStorageBuffer: GPUBuffer;

    timeUniformBuffer: GPUBuffer;

    moveLightsComputeBindGroupLayout: GPUBindGroupLayout;
    moveLightsComputeBindGroup: GPUBindGroup;
    moveLightsComputePipeline: GPUComputePipeline;

    // TODO-2: add layouts, pipelines, textures, etc. needed for light clustering here
    clusterBindGroupLayout: GPUBindGroupLayout;
    clusterBindGroup: GPUBindGroup;
    clusterComputePipeline: GPUComputePipeline;
    clusterBuffer: GPUBuffer;

    constructor(camera: Camera) {
        this.camera = camera;

        this.lightSetStorageBuffer = device.createBuffer({
            label: "lights",
            size: 16 + this.lightsArray.byteLength, // 16 for numLights + padding
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
        });
        this.populateLightsBuffer();
        this.updateLightSetUniformNumLights();

        this.timeUniformBuffer = device.createBuffer({
            label: "time uniform",
            size: 4,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });

        this.moveLightsComputeBindGroupLayout = device.createBindGroupLayout({
            label: "move lights compute bind group layout",
            entries: [
                { // lightSet
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "storage" }
                },
                { // time
                    binding: 1,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "uniform" }
                }
            ]
        });

        this.moveLightsComputeBindGroup = device.createBindGroup({
            label: "move lights compute bind group",
            layout: this.moveLightsComputeBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.lightSetStorageBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.timeUniformBuffer }
                }
            ]
        });

        this.moveLightsComputePipeline = device.createComputePipeline({
            label: "move lights compute pipeline",
            layout: device.createPipelineLayout({
                label: "move lights compute pipeline layout",
                bindGroupLayouts: [ this.moveLightsComputeBindGroupLayout ]
            }),
            compute: {
                module: device.createShaderModule({
                    label: "move lights compute shader",
                    code: shaders.moveLightsComputeSrc
                }),
                entryPoint: "main"
            }
        });

        // TODO-2: initialize layouts, pipelines, textures, etc. needed for light clustering here
        const maxLights = shaders.constants.maxLightsPerCluster;

        const numClusters = shaders.constants.numClustersX * shaders.constants.numClustersY * shaders.constants.numClustersZ;
        const clusterStructSize = 16 + 16 + 16 + 4 * maxLights; // numLights (4) + padding (4) + lightIndices (4 * maxLightsPerCluster)
        const clusterBufferSize = numClusters *  Math.ceil(clusterStructSize / 16) * 16; // + 16 is for numClusters u32 + padding

        this.clusterBuffer = device.createBuffer({
            label: "cluster buffer",
            size: clusterBufferSize,
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC
        });

        this.clusterBindGroupLayout = device.createBindGroupLayout({
            label: "clustering compute bind group layout",
            entries: [
                { binding: 0,
                  visibility: GPUShaderStage.COMPUTE,
                  buffer: { type: "uniform" } // cameraUniforms
                },
                { binding: 1,
                  visibility: GPUShaderStage.COMPUTE,
                  buffer: { type: "read-only-storage" } // lightSet
                },
                { binding: 2,
                  visibility: GPUShaderStage.COMPUTE,
                  buffer: { type: "storage" } // clusterSet
                }
            ]
        });

        this.clusterBindGroup = device.createBindGroup({
            label: "clustering compute bind group",
            layout: this.clusterBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.clusterBuffer }
                }
            ]
        });

        this.clusterComputePipeline = device.createComputePipeline({
            label: "clustering compute pipeline",
            layout: device.createPipelineLayout({
                label: "clustering compute pipeline layout",
                bindGroupLayouts: [ this.clusterBindGroupLayout ]
            }),
            compute: {
                module: device.createShaderModule({
                    label: "clustering compute shader",
                    code: shaders.clusteringComputeSrc
                }),
                entryPoint: "main"
            }
        });

        // DEBUGGING
async function readClusterCounts(device: GPUDevice, queue: GPUQueue, clusterBuffer: GPUBuffer) {
  // read the first N bytes (cap reasonably)
  const readBytes = Math.min(clusterBufferSize, 1024); // inspect first 1KB
  const readback = device.createBuffer({
    size: readBytes,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
  });

  // Encode copy and submit
  const enc = device.createCommandEncoder();
  enc.copyBufferToBuffer(clusterBuffer, 0, readback, 0, readBytes);
  queue.submit([enc.finish()]);

  // wait for GPU to finish work
  await queue.onSubmittedWorkDone();

  // map and read
  await readback.mapAsync(GPUMapMode.READ);
  const mapped = readback.getMappedRange();

  // print raw bytes (first 64)
  const u8 = new Uint8Array(mapped);
  const u32 = new Uint32Array(mapped);

  console.log("raw bytes (first 64):", Array.from(u8.slice(0,64)).map(b=>b.toString(16).padStart(2,'0')).join(' '));
  console.log("u32 view (first 16):", Array.from(u32.slice(0,16)));

  // Interpret clusters assuming layout:
  // per-cluster bytes: 16 (numLights + padding) + 16 (minAABB) + 16 (maxAABB) + 4*maxLights
  const clustersToInspect = Math.min(8, Math.floor(readBytes / clusterBufferSize));
  console.log("clustersToInspect:", clustersToInspect);
  for (let i = 0; i < clustersToInspect; ++i) {
    const baseByte = i * clusterBufferSize;
    const baseU32 = baseByte / 4;
    const numLights = u32[baseU32 + 0]; // first u32
    // minAABB floats begin at float index baseU32 + 4
    const minAABB = [new Float32Array(mapped, (baseByte + 16), 12).slice(0,3)]; // careful: typed view creation
    console.log(`cluster ${i}: baseByte=${baseByte} numLights=${numLights}`);
  }

  readback.unmap();
}
readClusterCounts(device, device.queue, this.clusterBuffer);
// DEBUGGING
    }

    private populateLightsBuffer() {
        for (let lightIdx = 0; lightIdx < Lights.maxNumLights; ++lightIdx) {
            // light pos is set by compute shader so no need to set it here
            const lightColor = vec3.scale(hueToRgb(Math.random()), Lights.lightIntensity);
            this.lightsArray.set(lightColor, (lightIdx * Lights.numFloatsPerLight) + 4);
        }

        device.queue.writeBuffer(this.lightSetStorageBuffer, 16, this.lightsArray);
    }

    updateLightSetUniformNumLights() {
        device.queue.writeBuffer(this.lightSetStorageBuffer, 0, new Uint32Array([this.numLights]));
    }

    doLightClustering(encoder: GPUCommandEncoder) {
        // TODO-2: run the light clustering compute pass(es) here
        // implementing clustering here allows for reusing the code in both Forward+ and Clustered Deferred
        const computePass = encoder.beginComputePass();
        computePass.setPipeline(this.clusterComputePipeline);
        computePass.setBindGroup(0, this.clusterBindGroup);

        computePass.dispatchWorkgroups(
            Math.ceil(shaders.constants.numClustersX / 8),
            Math.ceil(shaders.constants.numClustersY / 8),
            shaders.constants.numClustersZ
        );
        computePass.end();
    }

    // CHECKITOUT: this is where the light movement compute shader is dispatched from the host
    onFrame(time: number) {
        device.queue.writeBuffer(this.timeUniformBuffer, 0, new Float32Array([time]));

        // not using same encoder as render pass so this doesn't interfere with measuring actual rendering performance
        const encoder = device.createCommandEncoder();

        const computePass = encoder.beginComputePass();
        computePass.setPipeline(this.moveLightsComputePipeline);

        computePass.setBindGroup(0, this.moveLightsComputeBindGroup);

        const workgroupCount = Math.ceil(this.numLights / shaders.constants.moveLightsWorkgroupSize);
        computePass.dispatchWorkgroups(workgroupCount);

        computePass.end();

        device.queue.submit([encoder.finish()]);
    }
}
