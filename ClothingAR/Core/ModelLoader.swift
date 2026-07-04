import SceneKit
import ModelIO
import MetalKit

// MARK: - Bone Naming Lookup Table

/// 内置骨骼命名对照表，覆盖常见 DCC 工具的命名体系
enum BoneNameLookup {

    /// 4 种常见命名体系 → 各自的骨骼名映射
    /// Key: 通用骨骼名（我们代码内部用的）
    /// Value: 各体系的命名
    static let lookupTable: [String: [String]] = [
        // 髋部
        "hips":            ["mixamorig:Hips",       "Bip01_Pelvis",     "hips",            "Hips"],
        // 脊柱
        "spine":           ["mixamorig:Spine",      "Bip01_Spine",      "spine",           "Spine"],
        "spine1":          ["mixamorig:Spine1",     "Bip01_Spine1",     "spine.001",       "Spine1"],
        "spine2":          ["mixamorig:Spine2",     "Bip01_Spine2",     "spine.002",       "Spine2"],
        // 颈部
        "neck":            ["mixamorig:Neck",       "Bip01_Neck",       "neck",            "Neck"],
        // 左臂
        "left_shoulder":   ["mixamorig:LeftShoulder","Bip01_L_Clavicle","shoulder.L",     "LeftShoulder"],
        "left_elbow":      ["mixamorig:LeftArm",     "Bip01_L_UpperArm","upper_arm.L",     "LeftArm"],
        "left_wrist":      ["mixamorig:LeftHand",    "Bip01_L_Hand",    "hand.L",          "LeftHand"],
        // 右臂
        "right_shoulder":  ["mixamorig:RightShoulder","Bip01_R_Clavicle","shoulder.R",    "RightShoulder"],
        "right_elbow":     ["mixamorig:RightArm",    "Bip01_R_UpperArm","upper_arm.R",    "RightArm"],
        "right_wrist":     ["mixamorig:RightHand",   "Bip01_R_Hand",   "hand.R",          "RightHand"],
        // 左腿
        "left_hip":        ["mixamorig:LeftUpLeg",   "Bip01_L_Thigh",  "thigh.L",         "LeftUpLeg"],
        "left_knee":       ["mixamorig:LeftLeg",     "Bip01_L_Calf",   "shin.L",          "LeftLeg"],
        "left_ankle":      ["mixamorig:LeftFoot",    "Bip01_L_Foot",   "foot.L",          "LeftFoot"],
        // 右腿
        "right_hip":       ["mixamorig:RightUpLeg",  "Bip01_R_Thigh",  "thigh.R",         "RightUpLeg"],
        "right_knee":      ["mixamorig:RightLeg",    "Bip01_R_Calf",   "shin.R",          "RightLeg"],
        "right_ankle":     ["mixamorig:RightFoot",   "Bip01_R_Foot",   "foot.R",          "RightFoot"],
    ]

    /// 尝试匹配模型中的骨骼名到通用名
    /// - Returns: [通用骨骼名: 模型骨骼节点名]
    static func matchBones(from nodes: [SCNNode]) -> [String: String] {
        var result: [String: String] = [:]

        // 收集所有骨骼节点名
        let nodeNames = Set(nodes.map { $0.name ?? "" }).filter { !$0.isEmpty }

        for (genericName, candidates) in lookupTable {
            for candidate in candidates {
                // 精确匹配
                if nodeNames.contains(candidate) {
                    result[genericName] = candidate
                    break
                }
                // 模糊匹配（包含关系）
                if let match = nodeNames.first(where: { $0.localizedCaseInsensitiveContains(candidate) }) {
                    result[genericName] = match
                    break
                }
                // 反向模糊匹配
                if let match = nodeNames.first(where: { candidate.localizedCaseInsensitiveContains($0) }) {
                    result[genericName] = match
                    break
                }
            }
        }

        return result
    }
}

// MARK: - Load Result

struct ModelLoadResult {
    let scene: SCNScene
    let rootNode: SCNNode
    let boneNodes: [SCNNode]           // 所有骨骼节点
    let boneMapping: [String: String]  // [通用骨骼名: 模型骨骼节点名]
    let skinnerNodes: [SCNNode]        // 带蒙皮的网格节点
    let triangleCount: Int             // 三角面总数
    let materialCount: Int             // 材质球数量
}

// MARK: - ModelLoader

final class ModelLoader {

    // MARK: - Load Model

    /// 加载 DAE / SCN / GLB / FBX 文件
    /// - Parameter fileName: 文件名（不含扩展名），默认 "THIN_WELD_DECIMATED_new"
    /// - Parameter ext: 扩展名，默认 "glb"（Mixamo 转换后格式）
    /// - Returns: ModelLoadResult，失败返回 nil
    static func load(named fileName: String = "THIN_WELD_DECIMATED_new",
                     extension ext: String = "glb") -> ModelLoadResult? {

        var loadedScene: SCNScene?

        // ── 优先尝试 GLB (glTF binary) ──
        if ext == "glb" || ext == "gltf" {
            if let url = Bundle.main.url(forResource: fileName, withExtension: ext) {
                loadedScene = loadGLBAsset(url: url)
                if loadedScene != nil {
                    print("[ModelLoader] 成功加载 GLB: \(fileName).\(ext)")
                }
            }
        }

        // ── 尝试各种路径组合 ──
        if loadedScene == nil {
            let possibleNames: [(String, String)] = [
                (fileName, "glb"),
                (fileName, "dae"),
                (fileName, "scn"),
                ("FBX/\(fileName)", "fbx"),
            ]

            for (name, ex) in possibleNames {
                if let url = Bundle.main.url(forResource: name, withExtension: ex) {
                    do {
                        loadedScene = try SCNScene(url: url, options: [
                            .checkConsistency: true,
                            .flattenSceneHierarchy: false
                        ])
                        print("[ModelLoader] 成功加载: \(name).\(ex)")
                        break
                    } catch {
                        print("[ModelLoader] 加载失败 (\(name).\(ex)): \(error.localizedDescription)")
                    }
                }

                if let scene = SCNScene(named: "\(name).\(ex)") {
                    loadedScene = scene
                    print("[ModelLoader] 成功加载(named): \(name).\(ex)")
                    break
                }
            }
        }

        guard let scene = loadedScene else {
            print("[ModelLoader] ❌ 模型文件未找到。请确认 THIN WELD.dae 已放入 Resources/Models/ 目录")
            return nil
        }

        // ── 递归收集所有节点 ──
        var allNodes: [SCNNode] = []
        collectNodes(from: scene.rootNode, into: &allNodes)

        // ── 找骨骼节点 ──
        var boneNodes: [SCNNode] = []
        var skinnerNodes: [SCNNode] = []

        for node in allNodes {
            // 有 skinner → 蒙皮网格
            if node.skinner != nil {
                skinnerNodes.append(node)
            }
            // skeleton 子节点 → 骨骼
            if node.name?.lowercased().contains("skeleton") == true ||
               node.name?.lowercased().contains("bone") == true ||
               node.name?.lowercased().contains("joint") == true ||
               node.isSkeletonNode {
                collectSkeletonBones(from: node, into: &boneNodes)
            }
        }

        // 如果没找到明确的骨骼节点，遍历 skinner 的 bone 引用
        if boneNodes.isEmpty {
            for skinNode in skinnerNodes {
                if let skinner = skinNode.skinner {
                    boneNodes.append(contentsOf: skinner.bones)
                }
            }
            // 去重
            boneNodes = Array(Set(boneNodes))
        }

        // ── 打印骨骼列表 ──
        print("[ModelLoader] ===== 模型骨骼列表 (\(boneNodes.count) 个) =====")
        for bone in boneNodes {
            print("[ModelLoader]   骨骼: \(bone.name ?? "(未命名)")")
        }
        print("[ModelLoader] ===== 蒙皮网格: (\(skinnerNodes.count) 个) =====")
        for skin in skinnerNodes {
            let tris = countTriangles(skin.geometry)
            print("[ModelLoader]   网格: \(skin.name ?? "(未命名)") — \(tris) 三角面")
        }
        print("[ModelLoader] ==============================")

        // ── 骨骼命名匹配 ──
        let boneMapping = BoneNameLookup.matchBones(from: boneNodes)
        print("[ModelLoader] 骨骼匹配结果: \(boneMapping.count)/\(boneNodes.count) 个已识别")

        let unmatched = boneNodes.compactMap { $0.name }.filter { name in
            !boneMapping.values.contains(name)
        }
        if !unmatched.isEmpty {
            print("[ModelLoader] ⚠️ 未匹配的骨骼 (\(unmatched.count) 个):")
            for name in unmatched {
                print("[ModelLoader]   - \(name)")
            }
            print("[ModelLoader] 如需要，请在 BoneMapping.swift 中手动添加这些骨骼名的映射")
        }

        // ── 统计三角面数 ──
        var totalTris = 0
        for node in allNodes {
            totalTris += countTriangles(node.geometry)
        }

        // ── 统计材质 ──
        var materialNames = Set<String>()
        for node in allNodes {
            if let geo = node.geometry {
                for mat in geo.materials {
                    if let name = mat.name, !name.isEmpty {
                        materialNames.insert(name)
                    }
                }
                materialNames.insert("material_\(geo.materials.count)")
            }
        }

        print("[ModelLoader] 总三角面: \(totalTris), 材质: \(materialNames.count)")

        // ── 验证 ──
        if totalTris > 20000 {
            print("[ModelLoader] ⚠️ 三角面数 \(totalTris) 超过推荐的 20000，可能影响 iPhone X 性能")
        }
        if skinnerNodes.isEmpty {
            print("[ModelLoader] ❌ 模型没有蒙皮数据！请确保 FBX 导出时保留了骨骼和蒙皮权重")
        }

        // ── 材质修复：空贴图替补白色 ──
        for node in allNodes {
            guard let geo = node.geometry else { continue }
            for mat in geo.materials {
                if mat.diffuse.contents == nil || (mat.diffuse.contents as? String) == "" {
                    mat.diffuse.contents = UIColor.white
                }
            }
        }

        return ModelLoadResult(
            scene: scene,
            rootNode: scene.rootNode,
            boneNodes: boneNodes,
            boneMapping: boneMapping,
            skinnerNodes: skinnerNodes,
            triangleCount: totalTris,
            materialCount: materialNames.count
        )
    }

    // MARK: - GLB Loading

    /// 使用 ModelIO 加载 glTF/GLB 并转换为 SCNScene
    private static func loadGLBAsset(url: URL) -> SCNScene? {
        // MDLAsset 加载 GLB
        let asset = MDLAsset(url: url)
        guard asset.count > 0 else {
            print("[ModelLoader] MDLAsset 加载 GLB 返回空")
            return nil
        }

        // 转换为 SCNScene
        let scene = SCNScene(mdlAsset: asset)

        // 打印骨骼信息
        print("[ModelLoader] GLB loaded via ModelIO, root children: \(scene.rootNode.childNodes.count)")
        for (i, child) in scene.rootNode.childNodes.enumerated() {
            print("[ModelLoader]   child[\(i)]: \(child.name ?? "?") type: \(type(of: child))")
            if let skinner = child.skinner {
                print("[ModelLoader]     skinner bones: \(skinner.bones.count)")
                for bone in skinner.bones.prefix(5) {
                    print("[ModelLoader]       bone: \(bone.name ?? "?")")
                }
            }
        }

        return scene
    }

    // MARK: - Helpers

    private static func collectNodes(from node: SCNNode, into all: inout [SCNNode]) {
        all.append(node)
        for child in node.childNodes {
            collectNodes(from: child, into: &all)
        }
    }

    private static func collectSkeletonBones(from node: SCNNode, into bones: inout [SCNNode]) {
        bones.append(node)
        for child in node.childNodes {
            collectSkeletonBones(from: child, into: &bones)
        }
    }

    private static func countTriangles(_ geometry: SCNGeometry?) -> Int {
        guard let geo = geometry else { return 0 }
        var count = 0
        for element in geo.elements {
            count += element.primitiveCount
        }
        return count
    }
}

// MARK: - SCNNode Extension

extension SCNNode {
    /// 检查是否是骨架节点
    var isSkeletonNode: Bool {
        // skinner 存在时，它的 bones 数组中的节点都是骨骼
        // 递归检查是否有子骨骼绑定
        if skinner != nil { return true }
        for child in childNodes {
            if child.skinner != nil || child.isSkeletonNode {
                return true
            }
        }
        return false
    }
}
