//
//  CommsView.swift
//  TPU Mac
//
//  Created by ElectricS01  on 3/11/2023.
//

import Apollo
import NukeUI
import PrivateUploaderAPI
import SwiftUI

struct CommsView: View {
  @Binding var coreUser: StateQuery.Data.CurrentUser?
  @State private var chatsList: [ChatsQuery.Data.Chat] = []
  @State private var chatMessages: [MessagesQuery.Data.Message] = []
  @State private var chatOpen: Int = -1
  @State private var unreadId: Int = -1
  @State private var editingId: Int = -1
  @State private var replyingId: Int = -1
  @State private var inputMessage: String = ""
  @State private var editingMessage: String = ""
  //  @State private var hoverItem = -1
  
  func getMessages(chat: Int, completion: @escaping (Result<GraphQLResult<MessagesQuery.Data>, Error>) -> Void) {
    Network.shared.apollo.fetch(query: MessagesQuery(input: InfiniteMessagesInput(associationId: chat, position: GraphQLNullable(ScrollPosition.top), limit: 50)), cachePolicy: .fetchIgnoringCacheData) { result in
      switch result {
      case .success:
        completion(result)
      case .failure(let error):
        print("Failure! Error: \(error)")
        completion(result)
      }
    }
  }
  
  func getChat(chatId: Int?) {
    getMessages(chat: chatsList[chatId ?? 0].association?.id ?? 0) { result in
      switch result {
      case .success(let graphQLResult):
        if let unwrapped = graphQLResult.data {
          chatMessages = unwrapped.messages.reversed()
          chatOpen = chatId ?? -1
          if chatsList[chatOpen].unread != 0 {
            if let unreadMessageIndex = chatMessages.firstIndex(where: { $0.id == chatsList[chatOpen].association?.lastRead }) {
              unreadId = chatMessages[unreadMessageIndex + 1].id
            } else {
              unreadId = -1
            }
          }
        }
      case .failure(let error):
        print(error)
      }
    }
  }
  
  func getChats(completion: @escaping (Result<GraphQLResult<ChatsQuery.Data>, Error>) -> Void) {
    Network.shared.apollo.fetch(query: ChatsQuery(), cachePolicy: .fetchIgnoringCacheData) { result in
      switch result {
      case .success:
        completion(result)
      case .failure(let error):
        print("Failure! Error: \(error)")
        completion(result)
      }
    }
  }
  
  func sendMessage() {
    var replyId: GraphQLNullable<Int> = nil
    if replyingId != -1 { replyId = GraphQLNullable<Int>(integerLiteral: replyingId) }
    Network.shared.apollo.perform(mutation: SendMessageMutation(input: SendMessageInput(content: inputMessage, associationId: chatsList[chatOpen].association?.id ?? 0, attachments: [], replyId: replyId))) { result in
      switch result {
      case .success:
        replyingId = -1
        editingId = -1
        inputMessage = ""
      case .failure(let error):
        print("Failure! Error: \(error)")
      }
    }
  }
  
  func editMessage() {
    Network.shared.apollo.perform(mutation: EditMessageMutation(input: EditMessageInput(content: GraphQLNullable<String>(stringLiteral: editingMessage), attachments: [], messageId: editingId, associationId: chatsList[chatOpen].association?.id ?? 0))) { result in
      switch result {
      case .success:
        replyingId = -1
        editingId = -1
        inputMessage = ""
      case .failure(let error):
        print("Failure! Error: \(error)")
      }
    }
  }
  
  func pinMessage(messageId: Int, pinned: Bool) {
    Network.shared.apollo.perform(mutation: EditMessageMutation(input: EditMessageInput(attachments: [], messageId: messageId, associationId: chatsList[chatOpen].association?.id ?? 0, pinned: GraphQLNullable<Bool>(booleanLiteral: pinned)))) { result in
      switch result {
      case .success:
        replyingId = -1
        editingId = -1
        inputMessage = ""
      case .failure(let error):
        print("Failure! Error: \(error)")
      }
    }
  }
  
  func merge(message: MessagesQuery.Data.Message, previousMessage: MessagesQuery.Data.Message?) -> Bool {
    print(message.content)
    if message.userId == previousMessage?.userId && message.replyId == nil {
      return false
    }
    return true
  }
  
  func convertToMessage(subscriptionObject: UpdateMessagesSubscription.Data.OnMessage.Message) -> MessagesQuery.Data.Message {
    var messageData = DataDict(data: [:], fulfilledFragments: Set<ObjectIdentifier>())

    messageData["id"] = subscriptionObject.id
    messageData["createdAt"] = subscriptionObject.createdAt
    messageData["updatedAt"] = subscriptionObject.updatedAt
    messageData["chatId"] = subscriptionObject.chatId
    messageData["userId"] = subscriptionObject.userId
    messageData["content"] = subscriptionObject.content
    messageData["type"] = subscriptionObject.type
    messageData["emoji"] = subscriptionObject.emoji
    messageData["embeds"] = subscriptionObject.embeds
    messageData["reply"] = subscriptionObject.reply
    messageData["legacyUser"] = subscriptionObject.legacyUser
    messageData["user"] = subscriptionObject.user
    messageData["edited"] = subscriptionObject.edited
    messageData["editedAt"] = subscriptionObject.editedAt
    messageData["replyId"] = subscriptionObject.replyId
    messageData["legacyUserId"] = subscriptionObject.legacyUserId
    messageData["pinned"] = subscriptionObject.pinned
    messageData["readReceipts"] = subscriptionObject.readReceipts
    
    let message = MessagesQuery.Data.Message(_dataDict: messageData)

    return message
  }
  
  func messagesSubscription() {
    let subscription = UpdateMessagesSubscription()

    let handler = Network.shared.apollo.subscribe(subscription: subscription) { result in
      switch result {
      case .success(let graphQLResult):
        if let message = graphQLResult.data?.onMessage.message {
          print("Message received \(message.content)")
          let newMessage = convertToMessage(subscriptionObject: message)
          chatMessages.append(newMessage)
        }
      case .failure(let error):
        print("Failed to subscribe \(error)")
      }
    }
  }

  var body: some View {
    VStack {
      #if os(macOS)
      HSplitView {
        List {
          ForEach(0 ..< chatsList.count, id: \.self) { result in
            Button(action: { getChat(chatId: result) }) {
              HStack {
                ProfilePicture(avatar: chatsList[result].recipient?.avatar ?? chatsList[result].icon)
                Text(chatsList[result].recipient?.username ?? chatsList[result].name).lineLimit(1)
                Spacer()
                if chatsList[result].unread != 0 {
                  Text(String(chatsList[result].unread!))
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Color.red)
                    .cornerRadius(10)
                }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
        .frame(width: 150)
        .padding(EdgeInsets(top: -8, leading: -10, bottom: -8, trailing: 0))
        if chatOpen != -1 {
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(chatMessages.enumerated()), id: \.element) { index, message in
                  let dontMerge = merge(message: message, previousMessage: index != 0 ? chatMessages[index - 1] : nil)
                  Spacer(minLength: dontMerge ? 16 : 0)
                  if message.id == unreadId {
                    HStack {
                      VStack { Divider().background(.red) }
                      Text("New Message").foregroundStyle(.red)
                      VStack { Divider().background(.red) }
                    }
                  }
                  if message.reply != nil {
                    HStack {
                      Image(systemName: "arrow.turn.up.right").frame(width: 16, height: 16)
                      ProfilePicture(avatar: message.reply?.user?.avatar, size: 16)
                      Text(message.reply?.user?.username ?? "User has been deleted")
                      Text((message.reply?.content ?? "Message has been deleted").replacingOccurrences(of: "\n", with: "")).textSelection(.enabled).lineLimit(1)
                    }.padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0))
                  }
                  HStack(alignment: .top, spacing: 6) {
                    if dontMerge {
                      ProfilePicture(avatar: message.user?.avatar)
                    } else {
                      Spacer().frame(width: 32)
                    }
                    VStack {
                      if dontMerge {
                        HStack {
                          Text(message.user?.username ?? "User has been deleted")
                          Text(DateUtils.dateFormat(message.createdAt))
                        }.frame(minWidth: 0,
                                maxWidth: .infinity,
                                minHeight: 0,
                                maxHeight: 6,
                                alignment: .topLeading)
                      }
                      if editingId != message.id {
                        Text(.init(message.content ?? "Message has been deleted"))
                          .textSelection(.enabled)
                          .frame(minWidth: 0,
                                 maxWidth: .infinity,
                                 minHeight: 0,
                                 maxHeight: .infinity,
                                 alignment: .topLeading)
                          .lineLimit(nil)
                      } else {
                        TextField("Keep it civil!", text: $editingMessage)
                          .onSubmit {
                            editMessage()
                          }
                          .textFieldStyle(RoundedBorderTextFieldStyle())
                      }
                      ForEach(message.embeds, id: \.self) { embed in
                        if embed.media != [] {
                          LazyImage(url: URL(string: embed.media?[0].attachment == nil ? ("https://i.electrics01.com" + (embed.media?[0].proxyUrl ?? "")) : ("https://i.electrics01.com/i/" + (embed.media?[0].attachment ?? "")))) { state in
                            if let image = state.image {
                              image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                  if chatMessages.count != 0 {
                                    proxy.scrollTo(0, anchor: .bottom)
                                  }
                                }
                            } else if state.error != nil {
                              Color.red
                            } else {
                              ProgressView()
                            }
                          }.frame(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 400)
                        }
                      }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    }
                    Button(action: {
                      if replyingId != message.id {
                        replyingId = message.id
                      } else { replyingId = -1 }
                    }) {
                      Image(systemName: "arrowshape.turn.up.left.fill").frame(width: 16, height: 16)
                    }
                    Button(action: {
                      pinMessage(messageId: message.id, pinned: message.pinned)
                    }) {
                      Image(systemName: message.pinned ? "pin.slash.fill" : "pin.fill").frame(width: 16, height: 16)
                    }
                    if coreUser?.id == message.userId {
                      Button(action: {
                        replyingId = -1
                        if editingId != message.id {
                          editingId = message.id
                          editingMessage = message.content ?? ""
                        } else { editingId = -1 }
                      }) {
                        Image(systemName: "pencil").frame(width: 16, height: 16)
                      }
                    }
                  }.padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                  //                  .background(Color(hoverItem == message.id ? Color.primary : .clear))
                  //                  .onHover(perform: { _ in
                  //                    hoverItem = message.id
                  //                  })
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
              }
              .id(0)
              .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .topLeading
              )
              .onAppear {
                if chatMessages.count != 0 {
                  proxy.scrollTo(0, anchor: .bottom)
                }
              }
              .onChange(of: chatMessages) {
                proxy.scrollTo(0, anchor: .bottom)
              }
            }
            if replyingId != -1 {
              HStack {
                Image(systemName: "arrow.turn.up.right").frame(width: 16, height: 16)
                Text(chatMessages.last(where: { $0.id == replyingId })?.user?.username ?? "User has been deleted")
                Text(chatMessages.last(where: { $0.id == replyingId })?.content ?? "Message has been deleted")
                  .textSelection(.enabled)
                  .lineLimit(1)
                  .onAppear {
                    if chatMessages.count != 0 {
                      proxy.scrollTo(0, anchor: .bottom)
                    }
                  }
              }.padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0))
                .frame(minWidth: 0,
                       maxWidth: .infinity,
                       alignment: .topLeading)
            }
            TextField("Keep it civil!", text: $inputMessage)
              .onSubmit {
                sendMessage()
              }
              .textFieldStyle(RoundedBorderTextFieldStyle())
          }
          .navigationTitle(chatsList[chatOpen].recipient?.username ?? chatsList[chatOpen].name)
          List {
            ForEach(0 ..< chatsList[chatOpen].users.count, id: \.self) { result in
              Button(action: { print("Clicked: " + (chatsList[chatOpen].users[result].user?.username ?? "User's name could not be found")) }) {
                HStack {
                  ProfilePicture(avatar: chatsList[chatOpen].users[result].user?.avatar)
                  Text(chatsList[chatOpen].users[result].user?.username ?? "User's name could not be found")
                  Spacer()
                }.contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }.frame(width: 150)
            .padding(EdgeInsets(top: -8, leading: -10, bottom: -8, trailing: 0))
        } else {
          VStack {
            Spacer()
            HStack {
              Spacer()
              Text("Comms")
              Spacer()
            }
            Spacer()
          }
        }
      }
      .navigationTitle("Comms")
      .onAppear {
        getChats { result in
          switch result {
          case .success(let graphQLResult):
            if let unwrapped = graphQLResult.data {
              chatsList = unwrapped.chats
            }
          case .failure(let error):
            print(error)
          }
        }
        messagesSubscription()
      }
      #else
      List {
        ForEach(0 ..< chatsList.count, id: \.self) { result in
          Button(action: { getChat(chatId: result) }) {
            HStack {
              ProfilePicture(avatar: chatsList[result].recipient?.avatar ?? chatsList[result].icon)
              Text(chatsList[result].recipient?.username ?? chatsList[result].name).lineLimit(1)
              Spacer()
              if chatsList[result].unread != 0 {
                Text(String(chatsList[result].unread!))
                  .frame(minWidth: 16, minHeight: 16)
                  .background(Color.red)
                  .cornerRadius(10)
              }
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
      .padding(EdgeInsets(top: -8, leading: -10, bottom: -8, trailing: 0))
      if chatOpen != -1 {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(Array(chatMessages.enumerated()), id: \.element) { index, message in
                let dontMerge = merge(message: message, previousMessage: index != 0 ? chatMessages[index - 1] : nil)
                Spacer(minLength: dontMerge ? 16 : 0)
                if message.id == unreadId {
                  HStack {
                    VStack { Divider().background(.red) }
                    Text("New Message").foregroundStyle(.red)
                    VStack { Divider().background(.red) }
                  }
                }
                if message.reply != nil {
                  HStack {
                    Image(systemName: "arrow.turn.up.right").frame(width: 16, height: 16)
                    ProfilePicture(avatar: message.reply?.user?.avatar, size: 16)
                    Text(message.reply?.user?.username ?? "User has been deleted")
                    Text((message.reply?.content ?? "Message has been deleted").replacingOccurrences(of: "\n", with: "")).textSelection(.enabled).lineLimit(1)
                  }.padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0))
                }
                HStack(alignment: .top, spacing: 6) {
                  if dontMerge {
                    ProfilePicture(avatar: message.user?.avatar)
                  } else {
                    Spacer().frame(width: 32)
                  }
                  VStack {
                    if dontMerge {
                      HStack {
                        Text(message.user?.username ?? "User has been deleted")
                        Text(DateUtils.dateFormat(message.createdAt))
                      }.frame(minWidth: 0,
                              maxWidth: .infinity,
                              minHeight: 0,
                              maxHeight: 6,
                              alignment: .topLeading)
                    }
                    if editingId != message.id {
                      Text(.init(message.content ?? "Message has been deleted"))
                        .textSelection(.enabled)
                        .frame(minWidth: 0,
                               maxWidth: .infinity,
                               minHeight: 0,
                               maxHeight: .infinity,
                               alignment: .topLeading)
                        .lineLimit(nil)
                    } else {
                      TextField("Keep it civil!", text: $editingMessage)
                        .onSubmit {
                          editMessage()
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    ForEach(message.embeds, id: \.self) { embed in
                      if embed.media != [] {
                        LazyImage(url: URL(string: embed.media?[0].attachment == nil ? ("https://i.electrics01.com" + (embed.media?[0].proxyUrl ?? "")) : ("https://i.electrics01.com/i/" + (embed.media?[0].attachment ?? "")))) { state in
                          if let image = state.image {
                            image
                              .resizable()
                              .aspectRatio(contentMode: .fill)
                              .onAppear {
                                if chatMessages.count != 0 {
                                  proxy.scrollTo(0, anchor: .bottom)
                                }
                              }
                          } else if state.error != nil {
                            Color.red
                          } else {
                            ProgressView()
                          }
                        }.frame(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 400)
                      }
                    }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                  }
                  Button(action: {
                    if replyingId != message.id {
                      replyingId = message.id
                    } else { replyingId = -1 }
                  }) {
                    Image(systemName: "arrowshape.turn.up.left.fill").frame(width: 16, height: 16)
                  }
                  Button(action: {
                    pinMessage(messageId: message.id, pinned: message.pinned)
                  }) {
                    Image(systemName: message.pinned ? "pin.slash.fill" : "pin.fill").frame(width: 16, height: 16)
                  }
                  if coreUser?.id == message.userId {
                    Button(action: {
                      replyingId = -1
                      if editingId != message.id {
                        editingId = message.id
                        editingMessage = message.content ?? ""
                      } else { editingId = -1 }
                    }) {
                      Image(systemName: "pencil").frame(width: 16, height: 16)
                    }
                  }
                }.padding(4)
                //                  .background(Color(hoverItem == message.id ? Color.primary : .clear))
                //                  .onHover(perform: { _ in
                //                    hoverItem = message.id
                //                  })
              }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
            }
            .id(0)
            .frame(
              minWidth: 0,
              maxWidth: .infinity,
              minHeight: 0,
              maxHeight: .infinity,
              alignment: .topLeading
            )
            .onAppear {
              if chatMessages.count != 0 {
                proxy.scrollTo(0, anchor: .bottom)
              }
            }
            .onChange(of: chatMessages) {
              proxy.scrollTo(0, anchor: .bottom)
            }
          }
          if replyingId != -1 {
            HStack {
              Image(systemName: "arrow.turn.up.right").frame(width: 16, height: 16)
              Text(chatMessages.last(where: { $0.id == replyingId })?.user?.username ?? "User has been deleted")
              Text(chatMessages.last(where: { $0.id == replyingId })?.content ?? "Message has been deleted")
                .textSelection(.enabled)
                .lineLimit(1)
                .onAppear {
                  if chatMessages.count != 0 {
                    proxy.scrollTo(0, anchor: .bottom)
                  }
                }
            }.padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 0))
              .frame(minWidth: 0,
                     maxWidth: .infinity,
                     alignment: .topLeading)
          }
          TextField("Keep it civil!", text: $inputMessage)
            .onSubmit {
              sendMessage()
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .navigationTitle(chatsList[chatOpen].recipient?.username ?? chatsList[chatOpen].name)
        List {
          ForEach(0 ..< chatsList[chatOpen].users.count, id: \.self) { result in
            Button(action: { print("Clicked: " + (chatsList[chatOpen].users[result].user?.username ?? "User's name could not be found")) }) {
              HStack {
                ProfilePicture(avatar: chatsList[chatOpen].users[result].user?.avatar)
                Text(chatsList[chatOpen].users[result].user?.username ?? "User's name could not be found")
                Spacer()
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
        .padding(EdgeInsets(top: -8, leading: -10, bottom: -8, trailing: 0))
      } else {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Text("Comms")
            Spacer()
          }
          Spacer()
        }
        .navigationTitle("Comms")
        .onAppear {
          getChats { result in
            switch result {
            case .success(let graphQLResult):
              if let unwrapped = graphQLResult.data {
                chatsList = unwrapped.chats
              }
            case .failure(let error):
              print(error)
            }
          }
        }
      }
      #endif
    }
  }
}
