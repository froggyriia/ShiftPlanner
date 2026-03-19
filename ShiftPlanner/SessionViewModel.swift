import Foundation
import FirebaseAuth
import FirebaseFirestore

class SessionViewModel: ObservableObject {
    @Published var firebaseUser: User?
    @Published var userRole: String? = nil
    @Published var isLoading = true

    private let db = Firestore.firestore()

    init() {
        self.firebaseUser = Auth.auth().currentUser
        loadCurrentUserRole()
    }

    func refreshSession() {
        self.firebaseUser = Auth.auth().currentUser
        loadCurrentUserRole()
    }

    func loadCurrentUserRole() {
        guard let user = Auth.auth().currentUser else {
            self.userRole = nil
            self.isLoading = false
            return
        }

        self.isLoading = true

        db.collection("users").document(user.uid).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let data = snapshot?.data() {
                    self.firebaseUser = user
                    self.userRole = data["role"] as? String
                } else {
                    self.firebaseUser = user
                    self.userRole = nil
                }

                self.isLoading = false
            }
        }
    }

    func logout() {
        do {
            try Auth.auth().signOut()
            self.firebaseUser = nil
            self.userRole = nil
        } catch {
            print("Logout error: \(error.localizedDescription)")
        }
    }
}
