use 5.008008;
use ExtUtils::MakeMaker;


WriteMakefile(
    NAME              => 'POE::Component::WWW::Search::Mininova',
    VERSION_FROM      => 'lib/POE/Component/WWW/Search/Mininova.pm',
    PREREQ_PM         => {
    	POE			=> 0.9999,
    	'WWW::Search::Mininova' => 0.02,
    }, 
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/POE/Component/WWW/Search/Mininova.pm', 
       AUTHOR         => 'Zoffix Znet <zoffix@cpan.org>') : ()),
);
