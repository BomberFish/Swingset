//
//  State.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 17/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Combine
import SwiftUI
import StableDiffusion
import CoreML

let DEFAULT_MODEL = iosModel()
let DEFAULT_PROMPT = ""

enum GenerationState: Equatable {
    static func == (lhs: GenerationState, rhs: GenerationState) -> Bool {
        switch (lhs, rhs) {
        case (.startup, .startup): return true
        case (.running, .running): return true
        case (.complete, .complete): return true
        case (.userCanceled, .userCanceled): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
    
    var isRunning: Bool {
        switch self {
        case .running: return true
        default: return false
        }
    }
    
    var isComplete: Bool {
        switch self {
        case .complete: return true
        default: return false
        }
    }
    
    var isStartup: Bool {
        switch self {
        case .startup: return true
        default: return false
        }
    }
    
    case startup
    case running(StableDiffusionProgress?)
    case complete(String, CGImage?, UInt32, TimeInterval?)
    case userCanceled
    case failed(Error)
}

typealias ComputeUnits = MLComputeUnits

/// Schedulers compatible with StableDiffusionPipeline. This is a local implementation of the StableDiffusionScheduler enum as a String represetation to allow for compliance with NSSecureCoding.
public enum StableDiffusionScheduler: String {
    /// Scheduler that uses a pseudo-linear multi-step (PLMS) method
    case pndmScheduler
    /// Scheduler that uses a second order DPM-Solver++ algorithm
    case dpmSolverMultistepScheduler
    /// Scheduler for rectified flow based multimodal diffusion transformer models
    case discreteFlowScheduler

    func asStableDiffusionScheduler() -> StableDiffusion.StableDiffusionScheduler {
        switch self {
        case .pndmScheduler: return StableDiffusion.StableDiffusionScheduler.pndmScheduler
        case .dpmSolverMultistepScheduler: return StableDiffusion.StableDiffusionScheduler.dpmSolverMultistepScheduler
        case .discreteFlowScheduler: return StableDiffusion.StableDiffusionScheduler.discreteFlowScheduler
        }
    }
}

class GenerationContext: ObservableObject {
    let scheduler = StableDiffusionScheduler.dpmSolverMultistepScheduler

    @Published var pipeline: Pipeline? = nil {
        didSet {
            if let pipeline = pipeline {
                progressSubscriber = pipeline
                    .progressPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { progress in
                        guard let progress = progress else { return }
                        self.updatePreviewIfNeeded(progress)
                        self.state = .running(progress)
                    }
            }
        }
    }
    @Published var state: GenerationState = .startup
    
    @Published var positivePrompt = Settings.shared.prompt
    @Published var negativePrompt = Settings.shared.negativePrompt

    // FIXME: Double to support the slider component
    @Published var steps: Double = Settings.shared.stepCount
    @Published var numImages: Double = 1.0
    @Published var seed: UInt32 = Settings.shared.seed
    @Published var guidanceScale: Double = Settings.shared.guidanceScale
    @Published var previews: Double = runningOnMac ? Settings.shared.previewCount : 0.0
    @Published var disableSafety = true
    @Published var previewImage: CGImage? = nil

    @Published var computeUnits: ComputeUnits = Settings.shared.userSelectedComputeUnits ?? ModelInfo.defaultComputeUnits

    private var progressSubscriber: Cancellable?

    private func updatePreviewIfNeeded(_ progress: StableDiffusionProgress) {
        if previews == 0 || progress.step == 0 {
            previewImage = nil
        }

        if previews > 0, let newImage = progress.currentImages.first, newImage != nil {
            previewImage = newImage
        }
    }

    func generate() async throws -> GenerationResult {
        guard let pipeline = pipeline else { throw "No pipeline" }
        print(positivePrompt, negativePrompt, scheduler, steps, numImages, seed, guidanceScale, previews, disableSafety)
        return try pipeline.generate(
            prompt: positivePrompt,
            negativePrompt: negativePrompt,
            scheduler: scheduler,
            numInferenceSteps: Int(steps),
            seed: seed,
            numPreviews: Int(previews),
            guidanceScale: Float(guidanceScale),
            disableSafety: disableSafety
        )
    }
    
    func cancelGeneration() {
        pipeline?.setCancelled()
    }
}

class Settings: ObservableObject {
	static let shared = Settings()

	enum Keys: String {
		case model
		case safetyCheckerDisclaimer
		case computeUnits
		case prompt
		case negativePrompt
		case guidanceScale
		case stepCount
		case previewCount
		case seed
	}
	
	@AppStorage(Keys.model.rawValue) private var storedModel: String = iosModel().modelId
	var currentModel: ModelInfo {
		get { ModelInfo.from(modelId: storedModel) ?? iosModel() }
		set { storedModel = newValue.modelId }
	}

	@AppStorage(Keys.prompt.rawValue) var prompt: String = DEFAULT_PROMPT
	@AppStorage(Keys.negativePrompt.rawValue) var negativePrompt: String = ""
	@AppStorage(Keys.guidanceScale.rawValue) var guidanceScale: Double = 7.5
    @AppStorage(Keys.stepCount.rawValue) var stepCount: Double = 25.0
	@AppStorage(Keys.previewCount.rawValue) var previewCount: Double = 5
	@AppStorage(Keys.seed.rawValue) private var storedSeed: String = "0"
	var seed: UInt32 {
		get { UInt32(storedSeed) ?? 0 }
		set { storedSeed = String(newValue) }
	}
	@AppStorage(Keys.safetyCheckerDisclaimer.rawValue) var safetyCheckerDisclaimerShown: Bool = false

	@AppStorage(Keys.computeUnits.rawValue) private var storedComputeUnits: Int = -1
	var userSelectedComputeUnits: ComputeUnits? {
		get { storedComputeUnits == -1 ? nil : ComputeUnits(rawValue: storedComputeUnits) }
		set { storedComputeUnits = newValue?.rawValue ?? -1 }
	}

	private init() {}

	public func applicationSupportURL() -> URL {
		let fileManager = FileManager.default
		guard let appDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
			return URL.applicationSupportDirectory
		}
		do {
			try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
		} catch {
			print("Error creating application support directory: \(error)")
			return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		}
		return appDirectoryURL
	}

	func tempStorageURL() -> URL {
		let tmpDir = applicationSupportURL().appendingPathComponent("hf-diffusion-tmp")
		if !FileManager.default.fileExists(atPath: tmpDir.path) {
			do {
				try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
			} catch {
				print("Failed to create temporary directory: \(error)")
				return FileManager.default.temporaryDirectory
			}
		}
		return tmpDir
	}
}
