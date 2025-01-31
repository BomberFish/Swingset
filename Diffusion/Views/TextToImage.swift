//
//  TextToImage.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine
import StableDiffusion
import ColorfulX

/// Presents "Share" + "Save" buttons on Mac; just "Share" on iOS/iPadOS.
/// This is because I didn't find a way for "Share" to show a Save option when running on macOS.
struct ShareButtons: View {
    var image: CGImage
    var name: String
    
    var filename: String {
        name.replacingOccurrences(of: " ", with: "_")
    }
    
    var body: some View {
        let imageView = Image(image, scale: 1, label: Text(name))

        if runningOnMac {
            HStack {
                ShareLink(item: imageView, preview: SharePreview(name, image: imageView))
                Button() {
                    guard let imageData = UIImage(cgImage: image).pngData() else {
                        return
                    }
                    do {
                        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).png")
                        try imageData.write(to: fileURL)
                        let controller = UIDocumentPickerViewController(forExporting: [fileURL])
                        
                        let scene = UIApplication.shared.connectedScenes.first as! UIWindowScene
                        scene.windows.first!.rootViewController!.present(controller, animated: true)
                    } catch {
                        print("Error creating file")
                    }
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
            }
        } else {
            ZStack(alignment: .center) {
                ShareLink(item: imageView, preview: SharePreview(name, image: imageView), label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding()
                        .padding(.bottom, 4) // wtf?
                })
            }
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial)
            .cornerRadius(.infinity)
        }
    }
}

struct CompleteView: View {
    public let lastPrompt: String
    public let image: CGImage?
    public let interval: TimeInterval?
    static let shiftDuration: TimeInterval = 5 // could totally put this in an initializer but whatever
    let timer = Timer.publish(every: shiftDuration, on: .main, in: .common).autoconnect()
    @State var shadowColor: Color = intelligenceColors[0]
    
    var body: some View {
        if image == nil {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.largeTitle.bold())
                Text("An unknown error occurred.")
                    .foregroundStyle(.secondary)
                    .font(.headline.weight(.medium))
            }
        } else {
            VStack(spacing: 32) {
                Image(image!, scale: 1, label: Text("generated"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(20)
                    .padding(.horizontal)
                    .shadow(color: shadowColor.opacity(0.7), radius: 24, x: 0, y: 0)
                    .onReceive(timer) { _ in
                        withAnimation(.easeInOut(duration: CompleteView.shiftDuration)) {
                            if shadowColor == intelligenceColors.last {
                                shadowColor = intelligenceColors[0]
                            } else {
                                shadowColor = intelligenceColors[(intelligenceColors.firstIndex(of: shadowColor)! + 1) % intelligenceColors.count]
                            }
                        }
                    }
                HStack {
                    Label(String(format: "%.1fs", interval ?? 0), systemImage: "stopwatch.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    ShareButtons(image: image!, name: lastPrompt)
                }.frame(maxHeight: 25)
            }
            .padding()
        }
    }
}

struct RunningView: View {
    var progress: StableDiffusionProgress?
    var body: some View {
        Group {
            if progress == nil || progress!.stepCount <= 0 {
                // The first time it takes a little bit before generation starts
                ProgressView()
            } else {
                let step = Int(progress!.step) + 1
                let fraction = min(Double(step) / Double(progress!.stepCount), 0.99)
                //            let label = "Step \(step) of \(progress!.stepCount)"
                HStack(spacing: 0) {
                    Text("Generating (")
                    Group {
                        if #available(iOS 15.0, *) {
                            Text("\(Int(fraction * 100))%")
                                .contentTransition(.numericText())
                        } else {
                            Text("\(Int(fraction * 100))%")
                        }
                    }
                    .fontWeight(.heavy)
                    Text(")")
                }
                .font(.title.bold())
            }
        }
        .animation(.snappy, value: progress)
    }
}

struct GenerationErrorPopover: View {
    var errorMessage: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.headline.weight(.medium))
            Text(errorMessage)
                .font(.caption)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(.infinity)
        .shadow(radius: 10)
    }
}

struct ImageWithPlaceholder: View {
    @EnvironmentObject var generation: GenerationContext
    @ObservedObject var settings = Settings.shared
    var state: Binding<GenerationState>
    
    @State var isAnimating = false
    
    @ViewBuilder var placeholder: some View {
        ZStack {
            //            ZStack(alignment: .center) {
            //                AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)
            //                    .frame(width: 300, height: 300)
            //                    .cornerRadius(.infinity)
            //                    .scaleEffect(isAnimating ? 1.05 : 0.95)
            //                    .rotationEffect(.degrees(isAnimating ? 359 : 0))
            //                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isAnimating)
            //                Circle()
            //                    .fill(.black)
            //                    .frame(width: 100, height: 100)
            //                    .scaleEffect(isAnimating ? 1.15 : 0.85)
            //                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: isAnimating)
            //            }
            //                .opacity(0.5)
            //                .blur(radius: 32)
            VStack(spacing: 10) {
                Text("Describe an image.")
                    .font(.title.weight(.bold))
                
                Menu(content: {
                    Picker("Choose model", selection: modelBinding) {
                        //                            Section("Choose model") {
                        let recommendedModel = iosModel()
                        ForEach(ModelInfo.MODELS, id: \.self) { model in
                            Group {
                                if !model.supportsNeuralEngine {
                                    Text("(CPU) \(model.modelVersion)")
                                } else {
                                    if model == recommendedModel {
                                        Text(model.modelVersion)
                                            .bold()
                                    } else {
                                        Text(model.modelVersion)
                                    }
                                }
                            }
                            .tag(model)
                        }
                        //                            }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: modelBinding.wrappedValue) { _ in
                        UIControl().sendAction(#selector(NSXPCConnection.suspend), to: UIApplication.shared, for: nil)
                        exit(0)
                    }
                }, label: {modelName})
            }
            //                .foregroundStyle(.secondary)
        }
    }
    
    let modelBinding: Binding<ModelInfo> = Binding(get: {
        Settings.shared.currentModel
    }, set: {
        Settings.shared.currentModel = $0
    })
    
    @ViewBuilder var modelName: some View {
        LinearGradient(colors: intelligenceColors, startPoint: .topLeading, endPoint: .bottomTrailing)
//            .frame(width: 150, height: 24)
            .frame(minWidth: 150, idealWidth: 150, maxWidth: 200, minHeight: 24, idealHeight: 24, maxHeight: 24)
            .mask {
                Label(modelBinding.wrappedValue.modelVersion, systemImage: intelligenceIcon)
                    .font(.caption.weight(.semibold))
            }
            .background(.ultraThinMaterial)
            .cornerRadius(.infinity)
            .onTapGesture {
                Haptic.shared.play(.light, intensity: 0.7)
            }
    }
    
    @State var showingFullError = false
        
    var body: some View {
        ZStack(alignment: .center) {
            switch state.wrappedValue {
            case .running, .startup, .userCanceled, .failed:
                let isRunning = state.wrappedValue.isRunning
                ColorfulView(color: .constant(intelligenceColors))
                    .frame(maxWidth: isRunning ? .infinity : 270, maxHeight: isRunning ? .infinity : 270)
                    .cornerRadius(isRunning ? 20 : .infinity)
                    .opacity(isRunning ? 1 : 0.6)
                    .blur(radius: isRunning ? 0 : 64)
            default:
                EmptyView()
            }
            GeometryReader { geo in
                Group {
                    switch state.wrappedValue {
                    case .startup, .failed(_), .userCanceled:
                        placeholder
                            .overlay(alignment: .center) {
                                switch state.wrappedValue {
                                case .failed(let err):
                                    HStack(alignment: .center) {
                                        Spacer()
                                        GenerationErrorPopover(errorMessage: "Error while generating: " + err.localizedDescription)
                                            .frame(maxWidth: geo.size.width / 1.1)
                                        .frame(maxWidth: geo.size.width / 1.1)
                                        Spacer()
                                    }
                                    .offset(y: -geo.size.height / 2)
                                    .animation(.smooth(duration: 0.3))
                                    .transition(.move(edge: .top))
                                case .userCanceled:
                                    HStack(alignment: .center) {
                                        Spacer()
                                        GenerationErrorPopover(errorMessage: "User canceled generation.")
                                            .frame(maxWidth: geo.size.width / 1.1)
                                        .frame(maxWidth: geo.size.width / 1.1)
                                        Spacer()
                                    }
                                    .offset(y: -geo.size.height / 2)
                                    .animation(.smooth(duration: 0.3))
                                    .transition(.move(edge: .top))
                                default:
                                    EmptyView()
                                }
                            }
                    case .running(let progress):
                        RunningView(progress: progress)
                    case .complete(let lastPrompt, let image, _, let interval):
                        CompleteView(lastPrompt: lastPrompt, image: image, interval: interval)
//                    case .userCanceled:
//                        Text("Generation canceled.")
//                            .foregroundStyle(.secondary)
//                            .font(.largeTitle.bold())
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.snappy, value: generation.previewImage)
        .animation(.snappy, value: state.wrappedValue)
        .animation(.snappy, value: showingFullError)
        .onChange(of: state.wrappedValue) { state in
            switch state {
            case .running(let progress):
                guard let progress = progress else { return }
//                Haptic.shared.play(.rigid, intensity: 0.25 + 0.75 * progress.step / Double(progress.stepCount))
            case .complete(_, _, _, _):
                Haptic.shared.notify(.success)
            case .userCanceled:
                Haptic.shared.play(.light)
            case .failed(_):
                Haptic.shared.notify(.error)
            default:
                break
            }
        }
    }
}

struct TextToImage: View {
    @EnvironmentObject var generation: GenerationContext

    @ObservedObject var settings = Settings.shared

    func submit() {
        print("Using SDXL:", generation.pipeline?.isXL as Any)
        if case .running = generation.state { return }
        Task {
            generation.state = .running(nil)
            do {
                let result = try await generation.generate()
                generation.state = .complete(generation.positivePrompt, result.image, result.lastSeed, result.interval)
            } catch {
                generation.state = .failed(error)
            }
        }
    }
    
    var disabledBinding: Binding<Bool> {
        .init {
            generation.state.isRunning
        } set: { _ in }
    }
    
    @ViewBuilder var textField: some View {
        PromptTextField(text: $generation.positivePrompt, isPositivePrompt: true, model: settings.currentModel.modelVersion, submitAction: submit, disabled: disabledBinding)
    }
    
    @ViewBuilder var textArea: some View {
        VStack(spacing: 8) {
            if #available(iOS 18.0, *) {
                textField
                    .writingToolsBehavior(.disabled)
            } else {
                textField
            }
            Label("Images may vary based on description.", systemImage: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
//            HStack {
//                PromptTextField(text: $generation.positivePrompt, isPositivePrompt: true, model: iosModel().modelVersion)
//                Button("Generate") {
//                    submit()
//                }
//                .padding()
//                .buttonStyle(.borderedProminent)
//            }
//            Spacer()
            ImageWithPlaceholder(state: $generation.state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    textArea
                }
//            Spacer()
            
        }
        .padding()
        .padding(.bottom, -8)
        .environmentObject(generation)
    }
}

#Preview("Prompt View") {
    TextToImage()
        .environmentObject(GenerationContext())
        .preferredColorScheme(.dark)
}

//#Preview("Generated Image") {
//    CompleteView(lastPrompt: "Labrador in the style of Vermeer", image: UIImage(named: "placeholder")!.cgImage, interval: 69.0)
//        .preferredColorScheme(.dark)
//}
