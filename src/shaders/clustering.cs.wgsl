// TODO-2: implement the light clustering compute shader

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;

// Unproject an NDC point (x,y,z in [-1,1]) to view space using invProj.
fn screenToViewSpace(screenCoord: vec2<f32>, depthNDC: f32) -> vec3<f32> {
    let ndcX = (screenCoord.x / cameraUniforms.canvasResolution.x) * 2.0 - 1.0;
    let ndcY = 1.0 - (screenCoord.y / cameraUniforms.canvasResolution.y) * 2.0;
    let ndc = vec4<f32>(ndcX, ndcY, depthNDC, 1.0);
    var viewPos = cameraUniforms.invProjMat * ndc;
    viewPos /= viewPos.w;
    return viewPos.xyz;
}

// Sphere-AABB intersection test (view-space)
fn sphereIntersectsAABB(center: vec3<f32>, r: f32, aMin: vec3<f32>, aMax: vec3<f32>) -> bool {
    let closest = clamp(center, aMin, aMax);
    let distSq = dot(closest - center, closest - center);
    return distSq <= r * r;
}

fn lineIntersectionPlane(a: vec3f, b: vec3f, planeZ: f32) -> vec3f {
    let ab = b - a;
    let t = (planeZ - a.z) / ab.z;
    return a + t * ab;
}

@compute
@workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // Cluster grid dimensions
    let clusterDims = vec3<u32>(${numClustersX}, ${numClustersY}, ${numClustersZ});
    if (gid.x >= clusterDims.x || gid.y >= clusterDims.y || gid.z >= clusterDims.z) {
        return;
    }

    let clusterIdx: u32 = gid.x + gid.y * clusterDims.x + gid.z * clusterDims.x * clusterDims.y;

    // Calculate screen-space bounds for this cluster
    let x0 = f32(gid.x) / f32(clusterDims.x) * cameraUniforms.canvasResolution.x;
    let x1 = f32(gid.x + 1u) / f32(clusterDims.x) * cameraUniforms.canvasResolution.x;
    let y0 = f32(gid.y) / f32(clusterDims.y) * cameraUniforms.canvasResolution.y;
    let y1 = f32(gid.y + 1u) / f32(clusterDims.y) * cameraUniforms.canvasResolution.y;

    // Logarithmic depth slicing
    let near = cameraUniforms.nearPlane;
    let far  = cameraUniforms.farPlane;
    let zSlice  = f32(gid.z) / f32(clusterDims.z);
    let zSlice1 = f32(gid.z + 1u) / f32(clusterDims.z);

    let zNear = -near * pow(far / near, zSlice);
    let zFar  = -near * pow(far / near, zSlice1);

    // Convert to view-space bounding box corners
    let clusterMinNear = screenToViewSpace(vec2<f32>(x0, y0), 0.0);
    let clusterMaxFar  = screenToViewSpace(vec2<f32>(x1, y1),  0.0);

    let eye = vec3f(0, 0, 0);
    let minPointNear = lineIntersectionPlane(eye, clusterMinNear, zNear);
    let minPointFar  = lineIntersectionPlane(eye, clusterMinNear, zFar);
    let maxPointNear = lineIntersectionPlane(eye, clusterMaxFar,  zNear);
    let maxPointFar  = lineIntersectionPlane(eye, clusterMaxFar,  zFar);

    let minBBox = vec3<f32>(
        min(clusterMinNear.x, clusterMaxFar.x),
        min(clusterMinNear.y, clusterMaxFar.y),
        min(zNear, zFar)
    );

    let maxBBox = vec3<f32>(
        max(clusterMinNear.x, clusterMaxFar.x),
        max(clusterMinNear.y, clusterMaxFar.y),
        max(zNear, zFar)
    );

    //let minBBox = min(min(minPointNear, minPointFar), min(maxPointNear, maxPointFar));
    //let maxBBox = max(max(minPointNear, minPointFar), max(maxPointNear, maxPointFar));

    // Assign lights to this cluster
    var counter: u32 = 0u;
    for (var lightIdx: u32 = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        if (counter >= ${maxLightsPerCluster}u) {
            break;
        }

        let light = lightSet.lights[lightIdx];
        let lightPosView = (cameraUniforms.viewMat * vec4<f32>(light.pos, 1.0)).xyz;

        if (sphereIntersectsAABB(lightPosView, ${lightRadius}, minBBox, maxBBox)) {
            clusterSet.clusters[clusterIdx].lightIndices[counter] = lightIdx;
            counter += 1u;
        }
    }

    clusterSet.clusters[clusterIdx].numLights = counter;
}