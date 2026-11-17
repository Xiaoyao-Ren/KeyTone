import datetime,hashlib,json,os,pathlib,secrets,shlex,subprocess
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID,ExtendedKeyUsageOID
root=pathlib.Path(os.environ.get("KEYTONE_SIGNING_DIR", pathlib.Path.home()/"Library/Application Support/KeyTone/Signing"))
root.mkdir(parents=True,exist_ok=True)
os.chmod(root,0o700)
config=root/'identity.json'
if config.exists():
 print('Existing KeyTone identity retained');raise SystemExit(0)
password=secrets.token_urlsafe(32)
(root/'keychain-password').write_text(password);os.chmod(root/'keychain-password',0o600)
key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'KeyTone Local Signing')])
now=datetime.datetime.now(datetime.timezone.utc)
cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=3650)).add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True).add_extension(x509.KeyUsage(digital_signature=True,content_commitment=False,key_encipherment=False,data_encipherment=False,key_agreement=False,key_cert_sign=False,crl_sign=False,encipher_only=None,decipher_only=None),critical=True).add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]),critical=True).add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()),critical=False).sign(key,hashes.SHA256()))
fingerprint=cert.fingerprint(hashes.SHA1()).hex().upper()
(root/'certificate.cer').write_bytes(cert.public_bytes(serialization.Encoding.DER))
bundle=root/'identity.p12';bundle.write_bytes(pkcs12.serialize_key_and_certificates(b'KeyTone Local Signing',key,cert,None,serialization.BestAvailableEncryption(password.encode())));os.chmod(bundle,0o600)
keychain=root/'KeyToneSigning.keychain-db'
original=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
def run(args):
 p=subprocess.run(args,text=True,capture_output=True)
 if p.returncode:raise RuntimeError(p.stderr.replace(password,'[redacted]'))
try:
 run(['security','create-keychain','-p',password,str(keychain)])
 run(['security','unlock-keychain','-p',password,str(keychain)])
 run(['security','import',str(bundle),'-k',str(keychain),'-f','pkcs12','-P',password,'-x','-T','/usr/bin/codesign'])
 run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
 config.write_text(json.dumps({'name':'KeyTone Local Signing','sha1':fingerprint,'keychain':str(keychain),'password_file':str(root/'keychain-password')},indent=2));os.chmod(config,0o600)
 print('Created dedicated local signing identity:',fingerprint)
 print('No global certificate trust settings were changed.')
finally:
 run(['security','list-keychains','-d','user','-s',*original])
 bundle.unlink(missing_ok=True)
