// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;
@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    // Determine cluster index based on fragment coordinates
    let clusterX = ${numClustersX}u;
    let clusterY = ${numClustersY}u;
    let clusterZ = ${numClustersZ}u;

    let screenPos = cameraUniforms.viewProjMat * vec4<f32>(in.pos, 1.0);
    let ndcPos = screenPos.xyz / screenPos.w;

    let viewPos = (cameraUniforms.viewMat * vec4<f32>(in.pos, 1.0)).xyz;

    // Compute cluster indices
    let cx = u32(clamp((ndcPos.x + 1.0) * 0.5 * f32(clusterX), 0.0, f32(clusterX - 1u)));
    let cy = u32(clamp((ndcPos.y + 1.0) * 0.5 * f32(clusterY), 0.0, f32(clusterY - 1u)));
    let cz = u32(clamp(log((-viewPos.z) / cameraUniforms.nearPlane) / log(cameraUniforms.farPlane / cameraUniforms.nearPlane) * f32(clusterZ), 0.0, f32(clusterZ - 1u)));

    let clusterIndex = cx + cy * clusterX + cz * clusterX * clusterY;

    // todo print the z slice to see if increasing
    let numTemp = f32(clusterSet.clusters[clusterIndex].numLights) / f32(${maxLightsPerCluster});


// DEBUGGING
    let x = f32(cx) / f32(${numClustersX});
    let y = f32(cy) / f32(${numClustersY});
    let z = f32(cz) / f32(${numClustersZ});

    //return vec4<f32>(0., 0., z, 1.0);
    // DEBUGGING

    //return vec4f(numTemp, numTemp, numTemp, 1f);

    // Retrieve cluster data

    var totalLightContrib = vec3f(0, 0, 0);
    let nor = normalize(in.nor);
    for (var i: u32 = 0u; i < clusterSet.clusters[clusterIndex].numLights; i = i + 1u) {
        let lightIdx = clusterSet.clusters[clusterIndex].lightIndices[i];
        let light = lightSet.lights[lightIdx];
        totalLightContrib += calculateLightContrib(light, in.pos, nor);
    }

    // let brightness = f32(cluster.numLights) / f32(${maxLightsPerCluster});

    // return vec4<f32>(vec3<f32>(brightness), 1.0);

let temp = -2.f * f32(cz) / f32(clusterZ);
    var finalColor = diffuseColor.rgb * totalLightContrib;
    return vec4(finalColor, 1);
}
