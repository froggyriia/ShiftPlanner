import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    
    @State private var isLoginMode = true
    
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var selectedRole = "employee"
    
    @State private var message = ""
    @State private var isLoading = false
    
    @State private var inviteCode = ""
    
    let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Shift Planner")
                    .font(.largeTitle)
                    .bold()
                
                Picker("Mode", selection: $isLoginMode) {
                    Text("Войти").tag(true)
                    Text("Зарегистрироваться").tag(false)
                }
                .pickerStyle(.segmented)
                
                if !isLoginMode {
                    TextField("Имя", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    Picker("Роль", selection: $selectedRole) {
                        Text("Сотрудник").tag("employee")
                        Text("Менеджер").tag("manager")
                    }
                    .pickerStyle(.segmented)
                    
                    if selectedRole == "employee" {
                            TextField("Код приглашения", text: $inviteCode)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                }
                
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                                
                SecureField("Пароль", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    handleAuth()
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isLoginMode ? "Войти" : "Создать аккаунт")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isLoading ||
                    email.isEmpty ||
                    password.isEmpty ||
                    (!isLoginMode && name.isEmpty) ||
                    (!isLoginMode && selectedRole == "employee" && inviteCode.isEmpty)
                )
                                
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                                
                Spacer()
            }
            .padding()
            
            
        }
    }
    
    private func handleAuth() {
        isLoading = true
        message = ""
            
        if isLoginMode {
            login()
        } else {
            signUp()
        }
    }
    
    private func createFirebaseUser(companyId: String?) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                isLoading = false
                message = "Sign up error: \(error.localizedDescription)"
                return
            }
            
            guard let user = result?.user else {
                isLoading = false
                message = "Failed to create user."
                return
            }
            
            var userData: [String: Any] = [
                "uid": user.uid,
                "name": name,
                "email": email,
                "role": selectedRole
            ]
            
            if let companyId = companyId {
                userData["companyId"] = companyId
            }
            
            db.collection("users").document(user.uid).setData(userData) { error in
                isLoading = false
                
                if let error = error {
                    message = "User created, but Firestore save failed: \(error.localizedDescription)"
                } else {
                    message = "Account created successfully."
                    session.refreshSession()
                }
            }
        }
    }
    
    private func signUp() {
        if selectedRole == "employee" {
            let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            
            db.collection("companies")
                .whereField("inviteCode", isEqualTo: trimmedCode)
                .getDocuments { snapshot, error in
                    if let error = error {
                        isLoading = false
                        message = "Failed to find company: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let companyDoc = snapshot?.documents.first else {
                        isLoading = false
                        message = "Company with this invite code not found."
                        return
                    }
                    
                    let companyId = companyDoc.documentID
                    createFirebaseUser(companyId: companyId)
                }
        } else {
            createFirebaseUser(companyId: nil)
        }
    }
    
    private func login() {
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                isLoading = false
                
                if let error = error {
                    message = "Login error: \(error.localizedDescription)"
                    return
                }
                
                if let user = result?.user {
                    message = "Logged in as \(user.email ?? "user")"
                    session.refreshSession()
                }
            }
        }
    
    
    
}

#Preview {
    AuthView()
}
