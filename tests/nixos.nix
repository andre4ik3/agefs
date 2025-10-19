{
  name = "agefs";

  nodes.machine = {
    age = {
      identityPaths = [
        ./data/identity-age.txt
        ./data/identity-ssh.txt
      ];
      secrets = {
        age.file = ./data/secret-age.age;
        ssh.file = ./data/secret-ssh.age;
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("default.target")
    machine.succeed("cat /run/agenix/age | grep 'hello world'")
    machine.succeed("cat /run/agenix/ssh | grep 'hello world'")
  '';
}
