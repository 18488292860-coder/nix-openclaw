{
  outputs =
    { self }:
    {
      openclawPlugin = {
        name = "alpha";
        skills = [ ./skill ];
        packages = [ ];
        needs = { };
      };
    };
}
