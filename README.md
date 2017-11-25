# Cuffsert - CloudFormation CLI

The primary goal of cuffsert is to provide a quick "up-arrow-enter" loading of a CloudFormation stack with good feedback, removing the need to click through three pesky screens each time. It figures out whether the stack needs to be created or rolled-back and whether it needs to be deleted first.

## Getting started

Update a stack from a provided template without changing any parameters on the stack:

```bash
cuffsert -n my-stack ./my-template.json
```

If `./my-template.json` has no parameters the above command would create the stack if it did not already exist (so make sure you spell the stack name correctly :).

If you also want to provide a value for a stack parameter (whether on creation or update), you can use `-p key=value` to pass parameters. For all other parameters, cuffsert will tell CloudFormation to use the existing value.

Cuffsert can not (yet) be executed without a template in order to only change parameters.

## Parameters under version control

Cuffsert also allows encoding the parameters (and some commandline arguments) needed to load a template in a YAML file which you can put under versiin control. This takes CloudFormation the last mile to really become an infrastructure-as-code platform.

## Usage with file

cuffsert supports two basic use cases

Given the file cuffsert.yml:
```yaml
Format: v1
Suffix: webserver
Tags:
  - Name: Role
    Value: webserver
Variants:
  production:
    Tags:
      - Name: Environment
        Value: production
    Variants:
      eu1:
        Tags:
          - Name: DC
          - Value: eu1
        Parameters:
          - Name: ElasticIP
            Value: 1.2.3.4
      us1:
        Tags:
          - Name: DC
            Value: us1
        Parameters:
          - Name: ElasticIP
            Value: 5.6.7.8
```
you can invoke cuffsert like so:
```
cuffsert --metadata=./nginx-parameters.yml \
  --selector=production-us1 \
  ./nginx.yml
```

This will select tags `Role=webserver, Environment=production, DC=us1` and parameter `ElasticIP=5.6.7.8` and create or update the stack `production-us1-webserver` as necessary.

## Metadata file format

The metadata file consists of a hierarchy of configuration sections called "variants". Cuffsert splits the selector by [/-] and starts at the top of the metadata and tries to match the path elements against each  variants sections.

Each level can contain the following keys:

- **StackName**: Stack name used for creating a new stack and finding existing stack to update. If no StackName parameter is found, one will be constructed by joining lowercase variants values and basename of stack file. From the example at the top, stack name will be `production-eu1-webserver`.
- **Tags**: Tags applied at stack level.
- **Parameters**: Provide values for parameters that the stack needs.
- **Variations**: Each sub-key is a possible path element whose value is the hash for the next level.
- **DefaultPath**: You can supply a default selection for a particular path element which is given if none is supplied. Please be advised that having identical names at different hierarchical levels may lead to unexpected results.

Values from deeper levels merged onto values from higher levels to produce a configuration used to create/update the stack.

## Commandline options

    cuffsert [--stack-name=name] [--tag=k:v ...] [--parameter=k:v ...]
      [--metadata=directory | yml-file] [--metadata-path=path/to]
      cloudformation-file | cloudformation-template

All values set in the metadata file can be overridden on commandline.

`--stack-name=name (-n)` Explicity set the name of the generated stack.

`--tag=key:value (-t)` Override (or set) the value for a specific tag for the template.

`--parameter=key:value (-p)` Override (or set) the value for a specific parameter that is passed on template creation.

`--metadata=file (-m)` File or directory to read metadata from. Defaults to `cufsert/` or `cufsert.yml` relative to stack file.

`--selector=path-through-metadata (-P)` Path through variant keys to apply metadata from.

## AWS authentication

cuffsert assumes that the aws client library can authenticate your access via the normal means and makes no particular effort to aid the process, nor does it select revion for you.

## Future work

- Stack policies and policy overrides
- Find and delete resources that block delete or update
- provide detailed diffs on changes
