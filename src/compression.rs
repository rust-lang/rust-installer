use anyhow::{Context, Error};
use flate2::{read::GzDecoder, write::GzEncoder};
use rayon::prelude::*;
use std::{convert::TryFrom, io::Read, io::Write, path::Path};
use xz2::{read::XzDecoder, write::XzEncoder};

#[derive(Debug, Copy, Clone)]
pub enum CompressionFormat {
    Gz,
    Xz,
}

impl CompressionFormat {
    pub(crate) fn detect_from_path(path: impl AsRef<Path>) -> Option<Self> {
        match path.as_ref().extension().and_then(|e| e.to_str()) {
            Some("gz") => Some(CompressionFormat::Gz),
            Some("xz") => Some(CompressionFormat::Xz),
            _ => None,
        }
    }

    pub(crate) fn extension(&self) -> &'static str {
        match self {
            CompressionFormat::Gz => "gz",
            CompressionFormat::Xz => "xz",
        }
    }

    pub(crate) fn encode(&self, path: impl AsRef<Path>) -> Result<Box<dyn Encoder>, Error> {
        let mut os = path.as_ref().as_os_str().to_os_string();
        os.push(format!(".{}", self.extension()));
        let path = Path::new(&os);

        if path.exists() {
            crate::util::remove_file(path)?;
        }
        let file = crate::util::create_new_file(path)?;

        Ok(match self {
            CompressionFormat::Gz => Box::new(GzEncoder::new(file, flate2::Compression::best())),
            CompressionFormat::Xz => {
                // Note that preset 6 takes about 173MB of memory per thread, so we limit the number of
                // threads to not blow out 32-bit hosts.  (We could be more precise with
                // `MtStreamBuilder::memusage()` if desired.)
                let stream = xz2::stream::MtStreamBuilder::new()
                    .threads(Ord::min(num_cpus::get(), 8) as u32)
                    .preset(6)
                    .encoder()?;
                Box::new(XzEncoder::new_stream(file, stream))
            }
        })
    }

    pub(crate) fn decode(&self, path: impl AsRef<Path>) -> Result<Box<dyn Read>, Error> {
        let file = crate::util::open_file(path.as_ref())?;
        Ok(match self {
            CompressionFormat::Gz => Box::new(GzDecoder::new(file)),
            CompressionFormat::Xz => Box::new(XzDecoder::new(file)),
        })
    }
}

/// This struct wraps Vec<CompressionFormat> in order to parse the value from the command line.
#[derive(Debug, Clone)]
pub struct CompressionFormats(Vec<CompressionFormat>);

impl TryFrom<&'_ str> for CompressionFormats {
    type Error = Error;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        let mut parsed = Vec::new();
        for format in value.split(',') {
            match format.trim() {
                "gz" => parsed.push(CompressionFormat::Gz),
                "xz" => parsed.push(CompressionFormat::Xz),
                other => anyhow::bail!("unknown compression format: {}", other),
            }
        }
        Ok(CompressionFormats(parsed))
    }
}

impl Default for CompressionFormats {
    fn default() -> Self {
        Self(vec![CompressionFormat::Gz, CompressionFormat::Xz])
    }
}

impl CompressionFormats {
    pub(crate) fn iter(&self) -> impl Iterator<Item = CompressionFormat> + '_ {
        self.0.iter().map(|i| *i)
    }
}

pub(crate) trait Encoder: Send + Write {
    fn finish(self: Box<Self>) -> Result<(), Error>;
}

impl<W: Send + Write> Encoder for GzEncoder<W> {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        GzEncoder::finish(*self).context("failed to finish .gz file")?;
        Ok(())
    }
}

impl<W: Send + Write> Encoder for XzEncoder<W> {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        XzEncoder::finish(*self).context("failed to finish .xz file")?;
        Ok(())
    }
}

pub(crate) struct CombinedEncoder {
    encoders: Vec<Box<dyn Encoder>>,
}

impl CombinedEncoder {
    pub(crate) fn new(encoders: Vec<Box<dyn Encoder>>) -> Box<dyn Encoder> {
        Box::new(Self { encoders })
    }
}

impl Write for CombinedEncoder {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.write_all(buf)?;
        Ok(buf.len())
    }

    fn write_all(&mut self, buf: &[u8]) -> std::io::Result<()> {
        self.encoders
            .par_iter_mut()
            .map(|w| w.write_all(buf))
            .collect::<std::io::Result<Vec<()>>>()?;
        Ok(())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.encoders
            .par_iter_mut()
            .map(|w| w.flush())
            .collect::<std::io::Result<Vec<()>>>()?;
        Ok(())
    }
}

impl Encoder for CombinedEncoder {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        self.encoders
            .into_par_iter()
            .map(|e| e.finish())
            .collect::<Result<Vec<()>, Error>>()?;
        Ok(())
    }
}
