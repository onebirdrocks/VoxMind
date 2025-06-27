import SwiftUI

import SwiftUI

struct LimitlessLifelogsView: View {
    @State private var lifelogs: [Lifelog] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDatePicker = false
    @State private var selectedDate: Date? = nil

    struct Lifelog: Identifiable, Decodable {
        let id: String
        let title: String
        let startTime: String?
        let isStarred: Bool?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部栏
            HStack {
                Text(selectedDate == nil ? "Limitless Lifelogs" : "Lifelogs (\(dateString(selectedDate!)))")
                    .font(.headline)
                Spacer()
                Button(action: { showDatePicker = true }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .padding(.trailing, 8)
                .sheet(isPresented: $showDatePicker) {
                    VStack {
                        DatePicker("选择日期", selection: Binding(
                            get: { selectedDate ?? Date() },
                            set: { selectedDate = $0 }
                        ), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        Button("确定") {
                            showDatePicker = false
                            if let date = selectedDate {
                                loadLifelogs(for: date)
                            }
                        }
                        .padding(.bottom)
                    }
                    .presentationDetents([.medium])
                }
                Button(action: {
                    if let date = selectedDate {
                        loadLifelogs(for: date)
                    } else {
                        loadLifelogs()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .disabled(isLoading)
            }
            .padding(.bottom, 2)

            // 内容区
            if isLoading && lifelogs.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                Spacer()
            } else if lifelogs.isEmpty {
                Spacer()
                Text("暂无数据")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
            } else {
                List(lifelogs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.title)
                                .font(.body)
                                .lineLimit(2)
                            if let start = log.startTime {
                                Text(start.prefix(19).replacingOccurrences(of: "T", with: " "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if log.isStarred == true {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .refreshable {
                    if let date = selectedDate {
                        loadLifelogs(for: date)
                    } else {
                        loadLifelogs()
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { loadLifelogs() }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func loadLifelogs(for date: Date? = nil) {
        isLoading = true
        errorMessage = nil

        let apiKey = UserDefaults.standard.string(forKey: "LimitlessAIAPIKey") ?? ""
        guard !apiKey.isEmpty else {
            errorMessage = "请先在设置中填写 Limitless API Key"
            isLoading = false
            return
        }

        var urlString = "https://api.limitless.ai/v1/lifelogs?limit=20&includeMarkdown=false"
        if let date = date {
            urlString += "&date=\(dateString(date))"
        }
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = "网络错误: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    errorMessage = "无数据返回"
                }
                return
            }
            if let raw = String(data: data, encoding: .utf8) {
                print("🌐 Limitless 原始响应: \(raw)")
            }
            do {
                let decoded = try JSONDecoder().decode(LifelogsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.lifelogs = decoded.data?.lifelogs ?? []
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "解析失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    struct LifelogsResponse: Decodable {
        let data: LifelogsData?
        struct LifelogsData: Decodable {
            let lifelogs: [Lifelog]?
        }
    }
}