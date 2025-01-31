//
//  Loading.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine

func iosModel() -> ModelInfo {
    guard deviceSupportsQuantization else { return ModelInfo.v21Base }
    if deviceHas6GBOrMore { return ModelInfo.xlmbpChunked }
    if deviceHas8GBOrMore { return ModelInfo.xlmbp }
    
    return ModelInfo.v21Palettized
}

struct LoadingView: View {
    @StateObject var generation = GenerationContext()
    
    @ObservedObject var settings = Settings.shared

    @State private var preparationPhase: PipelineLoader.PipelinePreparationPhase = .downloading((0,0))
    @State private var downloadProgress: (Double,Double) = (0,0)
    
    enum CurrentView {
        case loading
        case textToImage
        case error(String)
    }
    @State private var currentView: CurrentView = .loading
    
    @State private var stateSubscriber: Cancellable?
    
    @State var color = false
    
    @State var showMoreLoadText = false
    
    func bytesToMB(_ bytes: Double) -> Double {
        bytes / 1024 / 1024
    }

    @ViewBuilder var loadingView: some View {
        Group {
            if preparationPhase == .readyOnDisk {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
//                        .controlSize(.large)
                        Text("Loading model. This may take a while.")
                            .font(.headline.weight(.medium))
                            .foregroundColor(color ? Color.gray : Color.white)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: color)
                            .animation(.snappy)
                            .transition(.opacity)
                            .opacity(showMoreLoadText ? 1 : 0)
                            .frame(minWidth: showMoreLoadText ? 0 : nil)
                }
                .onAppear {
                    color.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if preparationPhase == .readyOnDisk {
                            print("Model is still loading, this is probably a reinstall. Go grab a coffee.")
                            withAnimation(.snappy) {
                                showMoreLoadText = true
                            }
                        }
                    }
                }
            } else {
                VStack {
                    ProgressView("", value: downloadProgress.0, total: downloadProgress.1)
                        .labelsHidden()
                        .padding(.bottom, 6)
                    Group {
                        switch preparationPhase {
                        case .downloading:
                            Text("Downloading... (\(String(format: "%.2f", bytesToMB(downloadProgress.0))) MB / \(String(format: "%.2f", bytesToMB(downloadProgress.1))) MB)")
                        case .uncompressing:
                            Text("Decompressing...")
                        default:
                            Text("Loading...")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(color ? Color.gray : Color.white)
                    //                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: color)
                    .animation(.snappy, value: preparationPhase)
                    .onAppear {
                        color.toggle()
                    }
                }
                .padding(.horizontal, 50)
            }
        }
        .padding()
        .animation(.snappy, value: preparationPhase)
    }
    
    var body: some View {
        VStack {
            switch currentView {
            case .textToImage:
                TextToImage().transition(.opacity)
            case .error(let message):
                LoadingErrorPopover(errorMessage: message)
                    .transition(.move(edge: .top))
            case .loading:
                loadingView
            }
        }
        .animation(.snappy, value: currentView)
        .environmentObject(generation)
        .onAppear {
#if !targetEnvironment(simulator)
            Task.init {
                let loader = PipelineLoader(model: settings.currentModel)
                stateSubscriber = loader.statePublisher.sink { state in
                    DispatchQueue.main.async {
                        preparationPhase = state
                        switch state {
                        case .downloading(let progress):
                            downloadProgress = progress
                        case .uncompressing:
                            downloadProgress = (1,1)
                        case .readyOnDisk:
                            print("Started loading model \"\(settings.currentModel.modelVersion)\" from disk at \(Date()).")
                            downloadProgress = (1,1)
                        default:
                            break
                        }
                    }
                }
                do {
                    generation.pipeline = try await loader.prepare()
                    self.currentView = .textToImage
                } catch {
                    self.currentView = .error("Could not load model, error: \(error)")
                }
            }
#endif
        }
    }
}

// Required by .animation
extension LoadingView.CurrentView: Equatable {}

struct LoadingErrorPopover: View {
    var errorMessage: String

    var body: some View {
        ScrollView {
            Text(errorMessage)
                .font(.headline)
                .padding()
                .foregroundColor(.red)
                .textSelection(.enabled)
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
            .preferredColorScheme(.dark)
    }
}
