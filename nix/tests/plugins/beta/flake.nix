{
  outputs =
    { self }:
    {
      openclawPlugin = {
        name = "beta";
        skills = [ ./skill ];
        packages = [ ];
        needs = { };
      };
    };
}
