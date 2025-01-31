//
//  PromptTextField.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 22/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine
import StableDiffusion
import ColorfulX

struct PromptTextField: View {
    @ObservedObject var settings = Settings.shared
    @State private var output: String = ""
    @State private var input: String = ""
    @State private var typing = false
    @State private var tokenCount: Int = 0
    @State var isPositivePrompt: Bool = true
    @State private var tokenizer: BPETokenizer?
    @State private var currentModelVersion: String = ""
    
    @Binding var textBinding: String
    @Binding var model: String // the model version as it's stored in Settings
    
    @FocusState private var isFocused: Bool
    
    private let maxTokenCount = 77
    
    public var submitAction: () -> Void = {}
    
    
    @Binding var disabled: Bool
    
    
    private var modelInfo: ModelInfo? {
        ModelInfo.from(modelVersion: $model.wrappedValue)
    }
    
    private var pipelineLoader: PipelineLoader? {
        guard let modelInfo = modelInfo else { return nil }
        return PipelineLoader(model: modelInfo)
    }
    
    private var compiledURL: URL? {
        return pipelineLoader?.compiledURL
    }
    
    private var textColor: Color {
        switch tokenCount {
        case 0...65:
            return .green
        case 66...75:
            return .orange
        default:
            return .red
        }
    }
    
    // macOS initializer
//    init(text: Binding<String>, isPositivePrompt: Bool, model: Binding<String>) {
//        _textBinding = text
//        self.isPositivePrompt = isPositivePrompt
//        _model = model
//    }
    
    // iOS initializer
    init(text: Binding<String>, isPositivePrompt: Bool, model: String, submitAction: @escaping () -> Void) {
        _textBinding = text
        self.isPositivePrompt = isPositivePrompt
        _model = .constant(model)
        _disabled = .constant(false)
        self.submitAction = submitAction
    }
    
    init(text: Binding<String>, isPositivePrompt: Bool, model: String, submitAction: @escaping () -> Void, disabled: Binding<Bool>) {
        _textBinding = text
        self.isPositivePrompt = isPositivePrompt
        _model = .constant(model)
        _disabled = disabled
        self.submitAction = submitAction
    }
    
    @ViewBuilder var intelligenceGradient: some View {
        ColorfulView(color: .constant(intelligenceColors))
    }
    
    @State var showingPopover = false
    
    @ViewBuilder var settingsView: some View {
        VStack(alignment: .leading) {
            Label("Steps", systemImage: "square.stack.3d.up.fill")
            HStack {
                Slider(value: $settings.stepCount,
                       in: 1...200,
                       step: 1,
                       label: {
                    Label("Steps", systemImage: "square.stack.3d.up.fill")
                })
                .labelsHidden()
                Text("\(Int(settings.stepCount))")
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding()
    }
    
    var body: some View {
//        GeometryReader {geo in
        VStack {
            //#if os(macOS)
            //            TextField(isPositivePrompt ? "Positive prompt" : "Negative Prompt", text: $textBinding,
            //                      axis: .vertical)
            //            .lineLimit(20)
            //            .textFieldStyle(.squareBorder)
            //            .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
            //            .foregroundColor(textColor == .green ? .primary : textColor)
            //            .frame(minHeight: 30)
            //            if modelInfo != nil && tokenizer != nil {
            //                HStack {
            //                    Spacer()
            //                    if !textBinding.isEmpty {
            //                        Text("\(tokenCount)")
            //                            .foregroundColor(textColor)
            //                        Text(" / \(maxTokenCount)")
            //                    }
            //                }
            //                .onReceive(Just(textBinding)) { text in
            //                    updateTokenCount(newText: text)
            //                }
            //                .font(.caption)
            //            }
            //#else
            HStack {
                if isFocused {
                    Button {
//                        Haptic.shared.play(.medium)
                        isFocused = false
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 22, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .padding(10)
                    .frame(width: 50, height: 50)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(.infinity)
                }
                
                HStack {
                    intelligenceGradient
                        .frame(width: 25, height: 25)
                        .mask {
                            Image(systemName: intelligenceIcon)
                                .font(.system(size: 22, weight: .medium))
                        }
                    
                    TextField("Describe an image", text: $textBinding, axis: .horizontal)
                        .lineLimit(1, reservesSpace: true)
                        .focused($isFocused)
                        .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: 20))
                        .foregroundColor(textColor == .green ? .primary : textColor)
                        .font(.subheadline)
                        .keyboardType(.default)
                        .submitLabel(.done)
                        .disabled(disabled)
                        .textInputAutocapitalization(.sentences)
                        .truncationMode(.tail)
                        .frame(height: 50)
                        
                    
                    Spacer()
                    
                    HStack(spacing: 1) {
                        if !textBinding.isEmpty {
                            Text("\(tokenCount)")
                                .foregroundColor(textColor)
                            Text("/")
                            Text("\(maxTokenCount)")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    
                    if !textBinding.isEmpty && !disabled {
                        Button {
                            Haptic.shared.play(.soft, intensity: 5.0)
                            isFocused = false
                            submitAction()
                        } label: {
                            intelligenceGradient
                                .frame(width: 25, height: 25)
                                .mask {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 22, weight: .medium))
                                }
                        }
                        .font(.title2.weight(.medium))
                    }
                }
                .padding(10)
                .frame(height: 50)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(.infinity)
                
                if !isFocused {
                    Button {
                        Haptic.shared.play(.light)
                        showingPopover.toggle()
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 22, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .padding(10)
                    .frame(width: 50, height: 50)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(.infinity)
                    .popover(isPresented: $showingPopover, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                        Group {
                            if #available(iOS 16.4, *) {
                                settingsView
                                    .presentationCompactAdaptation(.popover)
                                    .presentationBackground(.ultraThinMaterial)
                            } else {
                                settingsView
                                    .presentationDetents([.medium])
                            }
                        }
                        .frame(width: (UIDevice.current.orientation == .portrait ? UIScreen.main.bounds.width : UIScreen.main.bounds.height / 2) - 20)
                    }
                }
            }
            //            .font(.caption)
            .padding(.horizontal, 2)
            //#endif
        }
        .onChange(of: model) { model in
            updateTokenCount(newText: textBinding)
        }
        .onChange(of: isFocused) {
            Haptic.shared.play($0 ? .medium : .light)
        }
        .onAppear {
            updateTokenCount(newText: textBinding)
        }
        .onChange(of: textBinding) { text in
            updateTokenCount(newText: text)
        }
        .animation(.snappy, value: tokenCount)
        .animation(.snappy, value: textBinding)
        .animation(.snappy, value: model)
        .animation(.snappy, value: isFocused)
    }
    
    private func updateTokenCount(newText: String) {
        // ensure that the compiled URL exists
        guard let compiledURL = compiledURL else { return }
        // Initialize the tokenizer only when it's not created yet or the model changes
        // Check if the model version has changed
        let modelVersion = $model.wrappedValue
        if modelVersion != currentModelVersion {
            do {
                tokenizer = try BPETokenizer(
                    mergesAt: compiledURL.appendingPathComponent("merges.txt"),
                    vocabularyAt: compiledURL.appendingPathComponent("vocab.json")
                )
                currentModelVersion = modelVersion
            } catch {
                print("Failed to create tokenizer: \(error)")
                return
            }
        }
        let (tokens, _) = tokenizer?.tokenize(input: newText) ?? ([], [])
        
        DispatchQueue.main.async {
            self.tokenCount = tokens.count
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var txt = "The void The void The void The void The void The void The void The void The void The void The void The void "
    @Previewable @State var model = "t"
    VStack {
        Spacer()
        PromptTextField(text: $txt, isPositivePrompt: true, model: model, submitAction: {})
    }
        .preferredColorScheme(.dark)
        .padding()
}
