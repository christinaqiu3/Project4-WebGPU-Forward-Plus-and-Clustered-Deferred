// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.

@group (${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group (${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group (${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group (1) @binding(0) var positionTexture: texture_2d<f32>;// deffered bind group layout
@group (1) @binding(1) var normalTexture: texture_2d<f32>;
@group (1) @binding(2) var albedoTexture: texture_2d<f32>;

@fragment
fn main(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = fragCoord.xy / cameraUniforms.canvasResolution;

    // Fetch G-buffer data
    let worldPos = textureLoad(positionTexture, vec2<i32>(fragCoord.xy), 0).xyz;
    let normal = normalize(textureLoad(normalTexture, vec2<i32>(fragCoord.xy), 0).xyz);
    let albedo = textureLoad(albedoTexture, vec2<i32>(fragCoord.xy), 0);

    // Determine cluster index
    let clusterDims = vec3<u32>(${numClustersX}, ${numClustersY}, ${numClustersZ});

    let viewPos = cameraUniforms.viewMat * vec4f(worldPos, 1.0);
    let viewProj = cameraUniforms.viewProjMat * vec4f(worldPos, 1.0);
    let ndcPos = (viewProj.xyz / viewProj.w) * 0.5 + vec3f(0.5, 0.5, 0.5);
    let clusterX = u32(clamp(ndcPos.x * f32(clusterDims.x), 0.0, f32(clusterDims.x - 1u)));
    let clusterY = u32(clamp(ndcPos.y * f32(clusterDims.y), 0.0, f32(clusterDims.y - 1u)));

    // Logarithmic depth slicing
    let near = cameraUniforms.nearPlane;
    let far  = cameraUniforms.farPlane;
    let viewDepth = -viewPos.z;
    let logDepth = log(far/near);
    let zSliceF = clamp(floor(log(-viewPos.z/near) / logDepth * f32(clusterDims.z)), 0.0, f32(clusterDims.z - 1u));
    let clusterZ = u32(zSliceF);

    let clusterIdx: u32 = clusterX + clusterY * clusterDims.x + clusterZ * clusterDims.x * clusterDims.y;

    var totalLightContrib = vec3f(0, 0, 0);

    let cluster = clusterSet.clusters[clusterIdx];
    for (var i: u32 = 0u; i < cluster.numLights; i = i + 1u) {
        let lightIdx = cluster.lightIndices[i];
        let light = lightSet.lights[lightIdx];

        totalLightContrib += calculateLightContrib(light, worldPos, normal);
    }

    var finalColor = albedo.rgb * totalLightContrib;
    return vec4(finalColor, 1);
}