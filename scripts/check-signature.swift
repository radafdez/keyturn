// Checks an EdDSA signature against a public key, the way the app will:
//
//     swift scripts/check-signature.swift <public-key> <file> <signature>
//
// make-appcast.sh runs it before publishing, so a release signed with a key
// that does not match the one built into the app fails here instead of on
// every Mac that tries to update.
//
// Comprueba una firma EdDSA contra una clave pública, igual que lo hará la app.
// make-appcast.sh la ejecuta antes de publicar: una versión firmada con una
// clave que no coincide con la de la app falla aquí, y no en cada Mac que
// intente actualizarse.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let publicKey = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      let file = FileManager.default.contents(atPath: arguments[2]) else {
    FileHandle.standardError.write(Data("Usage: check-signature.swift <public-key> <file> <signature>\n".utf8))
    exit(2)
}
guard key.isValidSignature(signature, for: file) else {
    FileHandle.standardError.write(Data("The signature does not match the app's SUPublicEDKey\n".utf8))
    exit(1)
}
print("Signature matches the app's key")
