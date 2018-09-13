require 'spec_helper_acceptance'
require 'rubygems/package'
require 'openssl'

class CA
  def initialize(subject, validity=24*60*60*30)
    # generate private key for ca
    @serial = 0x0
    @ca_key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse(subject)
    cert.not_before = Time.now - 60*60
    cert.not_after = Time.now + validity
    cert.public_key = @ca_key.public_key
    @serial += 1
    cert.serial = @serial
    cert.version = 2
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.extensions = [
      ef.create_extension("basicConstraints","CA:TRUE", true),
      ef.create_extension("subjectKeyIdentifier", "hash"),
      ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
      ef.create_extension("subjectAltName", "DNS:localhost", true),
    ]
    cert.add_extension ef.create_extension("authorityKeyIdentifier",
                                           "keyid:always,issuer:always")
    cert.sign @ca_key, OpenSSL::Digest::SHA256.new
    @ca_cert = cert
  end

  def ca_cert_pem
    @ca_cert.to_pem
  end

  def node_cert(subject, sans=[], validity=60*60)
    key = OpenSSL::PKey::RSA.new(2048)

    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = @ca_cert.issuer
    cert.not_before = Time.now - 60*60
    cert.not_after = Time.now + validity
    cert.public_key = key.public_key
    @serial += 1
    cert.serial = @serial
    cert.version = 2
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = @ca_cert
    cert.extensions = [
      ef.create_extension("basicConstraints","CA:FALSE", true),
      ef.create_extension("subjectKeyIdentifier", "hash"),
      ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
      ef.create_extension("subjectAltName", sans.join(','), true),
    ]
    cert.add_extension ef.create_extension("authorityKeyIdentifier",
                                           "keyid:always,issuer:always")
    cert.sign @ca_key, OpenSSL::Digest::SHA256.new
    return [cert.to_pem, key.to_pem]
  end
end

def prepare_host_files(host)
  file = Tempfile.new('params_tar')
  Gem::Package::TarWriter.new(file) do |writer|

    writer.add_file("etc/facter/facts.d/consul", 0700) do |f|
      content = <<EOS
#!/bin/bash
echo CONSUL_MASTER_TOKEN=7f0c1dae-aac7-44ea-abe8-d9411c9068cb
echo CONSUL_BOOTSTRAP_EXPECT=1
echo CONSUL_ENCRYPT=GFoaCb3cOofGJn2qwqvz8A==
EOS
      f.write(content)
    end

    writer.add_file("etc/vault/vault-test", 0600) do |f|
      token = <<EOS
dev-root-token
EOS
      f.write(token)
    end

    # generate cert, key
    cert, key = $ca.node_cert("CN=localhost",["DNS:localhost"])
    writer.add_file("etc/vault/tls/ca.pem", 0600) do |f|
      f.write($ca.ca_cert_pem)
    end
    writer.add_file("etc/vault/tls/tls.pem", 0600) do |f|
      f.write(cert)
    end
    writer.add_file("etc/vault/tls/tls-key.pem", 0600) do |f|
      f.write(key)
    end

    writer.add_file("etc/consul/consul-ca.pem", 0644) do |f|
	    f.write($ca.ca_cert_pem)
    end
    writer.add_file("etc/consul/consul.pem", 0644) do |f|
	    f.write(cert)
    end
    writer.add_file("etc/consul/consul-key.pem", 0644) do |f|
	    f.write(key)
    end
  end

  file.close
  rsync_to(host, file.path, "/tmp/archive.tar", {})
  on host, "tar xvf /tmp/archive.tar -C /"
  on host, "chown 871 /etc/consul/consul-key.pem"
  on host, "chown 871 /etc/vault/tls/tls-key.pem"
end

if hosts.length == 1
  describe '::vault_server' do
    before(:all) do
      hosts.each do |host|
        # Ensure /opt/bin is in the path
        on host, "echo -e '# ensure /opt/bin is in the path\nif ! echo $$PATH | grep -q /opt/bin ; then\n  export PATH=$PATH:/opt/bin\nfi\n' > /etc/profile.d/opt-bin.sh"
      end
    end

    $ca = CA.new("/CN=Vault CI CA")
    hosts.each do |host|
      prepare_host_files(host)
    end

    context 'test single node vault_server cluster' do
      # Using puppet_apply as a helper
      it 'should work with no errors based on the example' do
        pp = <<-EOS
class{'consul':
  ca_file => '/etc/consul/consul-ca.pem',
  cert_file => '/etc/consul/consul.pem',
  key_file => '/etc/consul/consul-key.pem',
}
class{'vault_server':
  environment => 'dev',
  cloud_provider => 'aws',
}
        EOS
        # Run it twice and test for idempotency
        apply_manifest(pp, :catch_failures => true)
        expect(apply_manifest(pp, :catch_failures => true).exit_code).to be_zero
      end
    end
  end
end
