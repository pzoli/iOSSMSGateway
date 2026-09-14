//
//  ContactHelper.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 12.
//

import Foundation
import Contacts

public class ContactHelper {
    public static func fetchContacts(completion: @escaping ([Contact]) -> Void) {
        let store = CNContactStore()
        
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        switch authorizationStatus {
        case .authorized:
            retrieveContacts(store: store, completion: completion)
        case .notDetermined:
            store.requestAccess(for: .contacts) { granted, error in
                if granted {
                    retrieveContacts(store: store, completion: completion)
                } else {
                    completion([])
                }
            }
        default:
            completion([])
        }
    }
    
    private static func retrieveContacts(store: CNContactStore, completion: @escaping ([Contact]) -> Void) {
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        
        var contacts: [Contact] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try store.enumerateContacts(with: request) { contact, stop in
                    let firstName = contact.givenName
                    let lastName = contact.familyName
                    let name = [lastName, firstName].filter({ !$0.isEmpty }).joined(separator: " ")
                    
                    let numbers = contact.phoneNumbers.map { $0.value.stringValue }
                    
                    if !name.isEmpty && !numbers.isEmpty {
                        contacts.append(Contact(name: name, numbers: numbers))
                    }
                }
                
                // Sort contacts alphabetically
                let sortedContacts = contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                completion(sortedContacts)
            } catch {
                print("Hiba a kontaktok lekérdezésekor: \(error)")
                completion([])
            }
        }
    }
}
