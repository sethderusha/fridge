//
//  ContentView.swift
//  fridge
//
//  Created by Seth DeRusha on 9/25/24.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isShowingScanner = false
    @State private var isShowingEntry = false
    @State private var barcode = ""
    @State private var apiResponse = ""
    @State private var manualEntryItem = Item()
    @State private var items: [Item] = []
    @State private var searchText = ""
    @State private var filterByDate = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "userApiKey") ?? ""
    @State private var isApiKeyPromptVisible = UserDefaults.standard.string(forKey: "userApiKey") == nil
    @State private var enteredApiKey: String = ""
    
    var filteredItems: [Item] {
        items.filter { item in
            (searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: "savedItems")
        }
    }

    func loadItems() {
        if let savedItemsData = UserDefaults.standard.data(forKey: "savedItems"),
           let decodedItems = try? JSONDecoder().decode([Item].self, from: savedItemsData) {
            items = decodedItems
        }
    }
    
    var body:  some View {
        NavigationView {
            VStack {
                HStack {
                    Button(action: {
                        isShowingScanner = true
                    }) {
                        Text("Scan Barcode")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        manualEntryItem = Item()
                        isShowingEntry = true
                    }) {
                        Text("Manual Entry")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                
                // Search bar
                TextField("Search by title", text: $searchText)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

                // Toggle to filter by expiration date
                Toggle(isOn: $filterByDate) {
                    Text("Filter by Expiration Date")
                }
                .padding(.horizontal)
                
                if items.isEmpty {
                    Text("Nothing in your fridge yet!")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                } else {
                    List {
                        if (!filteredItems.isEmpty) {
                            if (filterByDate) {
                                ForEach(filteredItems.sorted(by: { $0.expirationDate < $1.expirationDate })) { item in
                                    ItemRow(item: item)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteItem(item)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                editItem(item)
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                useOneItem(item)
                                            } label: {
                                                Label("Use One", systemImage: "minus.circle")
                                            }
                                            .tint(.green)
                                        }
                                }
                            } else {
                                ForEach(filteredItems) { item in
                                    ItemRow(item: item)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteItem(item)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                editItem(item)
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                useOneItem(item)
                                            } label: {
                                                Label("Use One", systemImage: "minus.circle")
                                            }
                                            .tint(.green)
                                        }
                                }
                            }
                        } else {
                            Text("No Items Found")
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Fridge")
            .sheet(isPresented: $isApiKeyPromptVisible) {
                VStack {
                    Text("Enter API Key\nGet key at https://upcdatabase.org")
                        .font(.headline)
                    TextField("API Key", text: $enteredApiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    Button(action: {
                        UserDefaults.standard.set(enteredApiKey, forKey: "userApiKey")
                        apiKey = enteredApiKey
                        isApiKeyPromptVisible = false
                    }) {
                        Text("Save")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            if apiKey.isEmpty {
                isApiKeyPromptVisible = true
            }
            loadItems()
        }
        .sheet(isPresented: $isShowingScanner) {
            BarcodeScannerView(scannedBarcode: $barcode, isShowingScanner: $isShowingScanner, completion: fetchProductDetails)
        }
        .sheet(isPresented: $isShowingEntry) {
            ManualEntryView(item: $manualEntryItem, isPresented: $isShowingEntry, onSave: { savedItem in
                if let index = items.firstIndex(where: { $0.id == savedItem.id }) {
                    items[index] = savedItem
                } else {
                    items.append(savedItem)
                }
                saveItems()
            })
        }
    }
    
    func deleteItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            saveItems()
        }
    }
    
    func editItem(_ item: Item) {
        manualEntryItem = item
        isShowingEntry = true
    }
    
    func useOneItem(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].quantity -= 1
            if items[index].quantity <= 0 {
                items.remove(at: index)
            }
            saveItems()
        }
    }
    
    func fetchProductDetails(_ scannedCode: String) {
        guard let apiKey = UserDefaults.standard.string(forKey: "userApiKey") else {
            print("API key not found.")
            return
        }
        let urlString = "https://api.upcdatabase.org/product/\(scannedCode)?apikey=\(apiKey)"
        print(urlString)
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received.")
                return
            }

            if var rawResponse = String(data: data, encoding: .utf8) {
                print("Raw Response: \(rawResponse)")
                
                if let jsonStartIndex = rawResponse.range(of: "{") {
                    rawResponse = String(rawResponse[jsonStartIndex.lowerBound...])
                    
                    if let jsonData = rawResponse.data(using: .utf8) {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                               let title = json["title"] as? String {
                                DispatchQueue.main.async {
                                    apiResponse = title
                                    manualEntryItem = Item(barcode: scannedCode, title: title)
                                    isShowingEntry = true
                                }
                            } else {
                                print("Failed to parse JSON.")
                                isShowingEntry = true
                            }
                        } catch {
                            print("JSON decoding error: \(error)")
                        }
                    }
                } else {
                    print("No JSON found in the response.")
                }
            }
        }
        task.resume()
    }
}

struct Item: Identifiable, Codable {
    var id = UUID()
    var barcode: String = ""
    var title: String = ""
    var quantity: Int = 1
    var expirationDate: Date = Date()
}

struct ItemRow: View {
    let item: Item
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(item.title)
                .font(.headline)
            Text("Barcode: \(item.barcode)")
                .font(.subheadline)
                .foregroundColor(.gray)
            Text("Quantity: \(item.quantity)")
                .font(.subheadline)
            Text("Expires: \(item.expirationDate, style: .date)")
                .font(.subheadline)
                .foregroundColor(.red)
        }
    }
}

struct ManualEntryView: View {
    @Binding var item: Item
    @Binding var isPresented: Bool
    var onSave: (Item) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Barcode", text: $item.barcode)
                TextField("Title", text: $item.title)
                Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 1...100)
                DatePicker("Expiration Date", selection: $item.expirationDate, displayedComponents: .date)
            }
            .navigationTitle("Item Details")
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Save") {
                    onSave(item)
                    isPresented = false
                }
            )
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedBarcode: String
    @Binding var isShowingScanner: Bool
    var completion: (String) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return viewController }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return viewController
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return viewController
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean13, .ean8, .code128]
        } else {
            return viewController
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = viewController.view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
        
        context.coordinator.captureSession = captureSession
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: BarcodeScannerView
        var captureSession: AVCaptureSession?

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                      let stringValue = readableObject.stringValue else { return }
                
                captureSession?.stopRunning()
                
                parent.scannedBarcode = stringValue
                parent.completion(stringValue)
                
                DispatchQueue.main.async {
                    self.parent.isShowingScanner = false
                }
            }
        }
    }
}
