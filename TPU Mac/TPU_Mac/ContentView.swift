//
//  ContentView.swift
//  TPU Mac
//
//  Created by ElectricS01  on 6/10/2023.
//

import Apollo
import KeychainSwift
import PrivateUploaderAPI
import SwiftUI

let keychain = KeychainSwift()

enum DateUtils {
  static let dateFormat: (String?) -> String = { date in
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    if let date = formatter.date(from: date ?? "") {
      formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
      return formatter.string(from: date)
    } else {
      return "Invalid Date"
    }
  }

  static let relativeFormat: (String?) -> String = { date in
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    if let date = formatter.date(from: date ?? "") {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      return formatter.localizedString(for: date, relativeTo: Date.now)
    } else {
      return "Invalid Date"
    }
  }
}

struct ContentView: View {
  @State private var showingLogin = keychain.get("token") == nil || keychain.get("token") == ""
  @State private var coreState: StateQuery.Data.CoreState?
  @State private var coreUser: StateQuery.Data.CurrentUser?
  @State var isPopover = false

  func getState() {
    Network.shared.apollo.fetch(query: StateQuery(), cachePolicy: .fetchIgnoringCacheData) { result in
      switch result {
      case .success(let graphQLResult):
        if let unwrapped = graphQLResult.data {
          coreState = unwrapped.coreState
          coreUser = unwrapped.currentUser
        }
      case .failure(let error):
        print("Failure! Error: \(error)")
      }
    }
  }

  var body: some View {
    if showingLogin {
      LoginSheet(showingLogin: $showingLogin)
    } else {
      #if os(macOS)
        NavigationSplitView {
          List {
            NavigationLink(destination: HomeView(coreState: $coreState)) {
              Label("Home", systemImage: "house")
            }
            NavigationLink(destination: SettingsView(showingLogin: $showingLogin, coreState: $coreState)) {
              Label("Settings", systemImage: "gear")
            }
            NavigationLink(destination: GalleryView(stars: .constant(false))) {
              Label("Gallery", systemImage: "photo.on.rectangle")
            }
            NavigationLink(destination: GalleryView(stars: .constant(true))) {
              Label("Stars", systemImage: "star")
            }
            NavigationLink(destination: CommsView(coreUser: $coreUser)) {
              Label("Comms", systemImage: "message")
            }
            NavigationLink(destination: AboutView()) {
              Label("About", systemImage: "info.circle")
            }
          }
        } detail: {
          HomeView(coreState: $coreState)
        }
        .onAppear {
          getState()
        }
        .toolbar(id: "nav") {
          ToolbarItem(id: "bell") {
            Button(action: { self.isPopover.toggle() }) {
              Label("Notifications", systemImage: "bell").help("Notifications")
              Text(String(coreUser?.notifications.filter { $0.dismissed == false }.count ?? 0))
            }.popover(isPresented: self.$isPopover, arrowEdge: .bottom) {
              VStack {
                Text("Notifications").font(.title)
                ForEach(coreUser?.notifications ?? [], id: \.self) { notification in
                  Divider()
                  HStack {
                    Text(notification.message)
                    Text(DateUtils.relativeFormat(notification.createdAt)).font(.subheadline).foregroundStyle(.gray)
                  }.frame(maxWidth: .infinity, alignment: .leading).frame(alignment: .top)
                }
              }.padding()
            }
          }
        }
      #else
        TabView {
          HomeView(coreState: $coreState).tabItem {
            Label("Home", systemImage: "house")
          }
          GalleryView(stars: .constant(false)).tabItem {
            Label("Gallery", systemImage: "photo.on.rectangle")
          }
          GalleryView(stars: .constant(true)).tabItem {
            Label("Stars", systemImage: "star")
          }
          CommsView(coreUser: $coreUser).tabItem {
            Label("Comms", systemImage: "message")
          }
          SettingsView(showingLogin: $showingLogin, coreState: $coreState).tabItem {
            Label("Settings", systemImage: "gear")
          }
        }
        .onAppear {
          getState()
        }
      #endif
    }
  }
}

struct LoginSheet: View {
  @Binding var showingLogin: Bool
  @State private var username: String = ""
  @State private var password: String = ""
  @State private var totp: String = ""
  @State private var errorMessage = ""

  func loginDetails() {
    Network.shared.apollo.perform(mutation: LoginMutation(input: LoginInput(username: username, password: password, totp: GraphQLNullable(stringLiteral: totp)))) { result in
      switch result {
      case .success(let graphQLResult):
        if graphQLResult.errors?[0].message == nil {
          keychain.set(graphQLResult.data?.login.token ?? "", forKey: "token")
          showingLogin = false
          return
        }
        errorMessage = graphQLResult.errors?[0].localizedDescription ?? "Error"
      case .failure(let error):
        print("Failure! Error: \(error)")
        errorMessage = error.localizedDescription
      }
    }
  }

  var body: some View {
    VStack {
      Text("Login").font(.title)
      TextField("Username", text: $username)
        .onSubmit {
          loginDetails()
        }
        .frame(width: 200)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .fixedSize(horizontal: true, vertical: false)
      SecureField("Password", text: $password)
        .onSubmit {
          loginDetails()
        }
        .frame(width: 200)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .fixedSize(horizontal: true, vertical: false)
      TextField("2FA code", text: $totp)
        .onSubmit {
          loginDetails()
        }
        .frame(width: 200)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .fixedSize(horizontal: true, vertical: false)
      Button("Login") {
        loginDetails()
      }
      Text(errorMessage)
        .foregroundColor(.red)
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .fixedSize(horizontal: false, vertical: true)
    }.padding()
  }
}

struct SettingsView: View {
  @Binding var showingLogin: Bool
  @Binding var coreState: StateQuery.Data.CoreState?

  var body: some View {
    VStack {
      Text("Settings")
      #if os(macOS)
        Text("Coming soon")
      #else
        Text("TPU iOS").font(.system(size: 32, weight: .semibold))
        Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (10/3/2024)")
        Text("Made by ElectricS01")
        Text("[Give it a Star on GitHub](https://github.com/ElectricS01/TPU-Mac)")
      #endif
      Button("Log out") {
        keychain.delete("token")
        showingLogin = true
      }
      .navigationTitle("Settings")
    }
  }
}

struct AboutView: View {
  var body: some View {
    VStack {
      Text("About")
        .navigationTitle("About")
      #if os(macOS)
        Text("TPU Mac").font(.system(size: 32, weight: .semibold))
      #else
        Text("TPU iOS").font(.system(size: 32, weight: .semibold))
      #endif
      Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (10/3/2024)")
      Text("Made by ElectricS01")
      Text("[Give it a Star on GitHub](https://github.com/ElectricS01/TPU-Mac)")
    }
  }
}

#Preview {
  ContentView()
}
